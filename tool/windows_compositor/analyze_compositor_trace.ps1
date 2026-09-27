[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$InputPath,

  [Parameter(Mandatory = $true)]
  [ValidateRange(1, [int]::MaxValue)]
  [int]$ProcessId,

  [string]$PresentMonPath,

  [Parameter(Mandatory = $true)]
  [string]$ReportPath,

  [string]$Scenario = 'unspecified',

  [ValidateRange(0, 10)]
  [double]$TrimEdgeSeconds = 1,

  [ValidateRange(0, 1000)]
  [double]$RefreshRateHz = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-UnresolvedPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $Path
  )
}

function Get-Percentile {
  param(
    [Parameter(Mandatory = $true)][double[]]$Values,
    [Parameter(Mandatory = $true)][ValidateRange(0, 100)][double]$Percent
  )

  $sorted = @($Values | Sort-Object)
  if ($sorted.Count -eq 0) {
    return $null
  }

  $rank = ($Percent / 100.0) * ($sorted.Count - 1)
  $lower = [math]::Floor($rank)
  $upper = [math]::Ceiling($rank)
  if ($lower -eq $upper) {
    return [double]$sorted[$lower]
  }

  return [double]$sorted[$lower] +
    (($rank - $lower) * ([double]$sorted[$upper] - [double]$sorted[$lower]))
}

function Get-Statistics {
  param([AllowEmptyCollection()][object[]]$Values)

  $finite = @(
    foreach ($value in $Values) {
      if ($null -eq $value) {
        continue
      }
      $number = [double]$value
      if (-not [double]::IsNaN($number) -and
          -not [double]::IsInfinity($number)) {
        $number
      }
    }
  )
  if ($finite.Count -eq 0) {
    return $null
  }

  $measure = $finite | Measure-Object -Minimum -Maximum -Average
  return [ordered]@{
    n = $finite.Count
    min = [math]::Round([double]$measure.Minimum, 4)
    p50 = [math]::Round([double](Get-Percentile $finite 50), 4)
    p95 = [math]::Round([double](Get-Percentile $finite 95), 4)
    p99 = [math]::Round([double](Get-Percentile $finite 99), 4)
    max = [math]::Round([double]$measure.Maximum, 4)
    mean = [math]::Round([double]$measure.Average, 4)
  }
}

function Get-PropertyStatistics {
  param(
    [Parameter(Mandatory = $true)][object[]]$Items,
    [Parameter(Mandatory = $true)][string]$Property
  )

  $values = @(
    foreach ($item in $Items) {
      $value = $item.$Property
      if ($null -ne $value) {
        $value
      }
    }
  )
  return Get-Statistics $values
}

function Get-Intervals {
  param(
    [Parameter(Mandatory = $true)][object[]]$Items,
    [Parameter(Mandatory = $true)][string]$Property
  )

  $result = [Collections.Generic.List[double]]::new()
  for ($index = 1; $index -lt $Items.Count; $index++) {
    $result.Add(
      [double]$Items[$index].$Property - [double]$Items[$index - 1].$Property
    )
  }
  return ,$result.ToArray()
}

function New-FrameMap {
  param(
    [Parameter(Mandatory = $true)][object[]]$Items,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $result = @{}
  foreach ($item in $Items) {
    $frameId = [long]$item.FrameId
    if ($result.ContainsKey($frameId)) {
      throw "$Name contains duplicate frame_id=$frameId."
    }
    $result[$frameId] = $item
  }
  return $result
}

function Get-QpcDeltaMilliseconds {
  param(
    [Parameter(Mandatory = $true)][long]$Start,
    [Parameter(Mandatory = $true)][long]$End,
    [Parameter(Mandatory = $true)][long]$Frequency
  )

  return (($End - $Start) * 1000.0) / $Frequency
}

$absoluteInput = Resolve-UnresolvedPath $InputPath
$absoluteReport = Resolve-UnresolvedPath $ReportPath
if (-not (Test-Path -LiteralPath $absoluteInput -PathType Leaf)) {
  throw "Trace does not exist: $absoluteInput"
}
if ([IO.Path]::GetExtension($absoluteInput) -ne '.etl') {
  throw 'InputPath must end in .etl.'
}
if ([IO.Path]::GetExtension($absoluteReport) -ne '.json') {
  throw 'ReportPath must end in .json.'
}
if (Test-Path -LiteralPath $absoluteReport) {
  throw "ReportPath already exists; preserve or remove it first: $absoluteReport"
}
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
  throw 'Trace analysis requires PowerShell 7 or newer. WPR capture does not.'
}

$xperfCommand = Get-Command xperf.exe -ErrorAction SilentlyContinue
if ($null -eq $xperfCommand) {
  $defaultXperf = Join-Path ${env:ProgramFiles(x86)} `
    'Windows Kits\10\Windows Performance Toolkit\xperf.exe'
  if (-not (Test-Path -LiteralPath $defaultXperf)) {
    throw 'xperf.exe was not found. Install the Windows Performance Toolkit.'
  }
  $xperf = $defaultXperf
} else {
  $xperf = $xperfCommand.Source
}

$toolkitPath = Split-Path -Parent $xperf
$catalogPath = Join-Path $toolkitPath 'Catalog'
$processingAssembly = Join-Path $toolkitPath `
  'CustomDataSources\XPerf\Microsoft.Windows.EventTracing.Processing.dll'
if (-not (Test-Path -LiteralPath $processingAssembly)) {
  throw "WPT TraceProcessing assembly was not found: $processingAssembly"
}
if (-not (Test-Path -LiteralPath (Join-Path $PSHOME 'ref'))) {
  throw "PowerShell reference assemblies were not found under $PSHOME\ref."
}

$reportDirectory = Split-Path -Parent $absoluteReport
if (-not (Test-Path -LiteralPath $reportDirectory)) {
  New-Item -ItemType Directory -Path $reportDirectory | Out-Null
}

$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) `
  "kirakara-compositor-analysis-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
$appEventDump = Join-Path $temporaryDirectory 'app-events.txt'
$presentMonCsv = Join-Path $temporaryDirectory 'presentmon.csv'

try {
  [Reflection.Assembly]::LoadFrom($processingAssembly) | Out-Null
  $references = @(
    (Get-ChildItem -LiteralPath (Join-Path $PSHOME 'ref') -Filter '*.dll').FullName
  ) + $processingAssembly
  Add-Type `
    -Path (Join-Path $PSScriptRoot 'compositor_trace_decoder.cs') `
    -ReferencedAssemblies $references

  Write-Host 'Decoding Show and DXGKRNL events...'
  $decoder = [Kirakara.WindowsCompositorTrace.CompositorTraceDecoder]::Run(
    $absoluteInput,
    $ProcessId,
    $toolkitPath,
    $catalogPath
  )

  Write-Host 'Decoding App TraceLogging events...'
  & $xperf `
    -i $absoluteInput `
    -o $appEventDump `
    -a dumper `
    -provider '{6862b681-4cdb-45e5-936c-05d82d83ef9a}'
  if ($LASTEXITCODE -ne 0) {
    throw "xperf App event dump failed with exit code $LASTEXITCODE."
  }

  $appEvents = [ordered]@{
    TextureCallback = [Collections.Generic.List[object]]::new()
    FrameAvailable = [Collections.Generic.List[object]]::new()
    TextureAcquire = [Collections.Generic.List[object]]::new()
    FlutterFramePresented = [Collections.Generic.List[object]]::new()
  }
  foreach ($line in [IO.File]::ReadLines($appEventDump)) {
    if (-not $line.StartsWith('Kirakara.App.StageTexture/')) {
      continue
    }

    $fields = @($line.Split(',') | ForEach-Object { $_.Trim() })
    if ($fields.Count -lt 13 -or
        $fields[2] -notmatch "\($ProcessId\)$") {
      continue
    }

    switch ($fields[0]) {
      'Kirakara.App.StageTexture/TextureCallback/' {
        $appEvents.TextureCallback.Add([pscustomobject]@{
          TimeMs = [double]$fields[1] / 1000.0
          Qpc = [long]$fields[9]
          Generation = [long]$fields[10]
          FrameId = [long]$fields[11]
        })
      }
      'Kirakara.App.StageTexture/FrameAvailable/' {
        $appEvents.FrameAvailable.Add([pscustomobject]@{
          TimeMs = [double]$fields[1] / 1000.0
          Qpc = [long]$fields[9]
          Generation = [long]$fields[10]
          FrameId = [long]$fields[11]
        })
      }
      'Kirakara.App.StageTexture/TextureAcquire/' {
        $appEvents.TextureAcquire.Add([pscustomobject]@{
          TimeMs = [double]$fields[1] / 1000.0
          Qpc = [long]$fields[9]
          Generation = [long]$fields[10]
          FrameId = [long]$fields[11]
          Advanced = [bool]::Parse($fields[12])
        })
      }
      'Kirakara.App.StageTexture/FlutterFramePresented/' {
        if ($fields.Count -lt 16) {
          throw "Malformed FlutterFramePresented line: $line"
        }
        $appEvents.FlutterFramePresented.Add([pscustomobject]@{
          TimeMs = [double]$fields[1] / 1000.0
          Qpc = [long]$fields[9]
          PresentationId = [long]$fields[10]
          AcquireSequence = [long]$fields[11]
          Generation = [long]$fields[12]
          FrameId = [long]$fields[13]
          AcquiredSincePreviousPresent = [bool]::Parse($fields[14])
        })
      }
    }
  }

  $stagePublishes = @(
    $decoder.NativeStageEvents |
      Where-Object Name -eq 'StagePublish' |
      Sort-Object TimeMs
  )
  $previewPublications = @(
    $decoder.NativeStageEvents |
      Where-Object Name -eq 'PreviewPublication' |
      Sort-Object TimeMs
  )
  $previewCallbacks = @(
    $decoder.NativeStageEvents |
      Where-Object Name -eq 'PreviewCallback' |
      Sort-Object TimeMs
  )
  if ($stagePublishes.Count -lt 2) {
    throw "Fewer than two StagePublish events were found for PID $ProcessId."
  }

  $firstStage = $stagePublishes[0]
  $lastStage = $stagePublishes[-1]
  $qpcFrequency = [long][math]::Round(
    ($lastStage.Qpc - $firstStage.Qpc) /
      (($lastStage.TimeMs - $firstStage.TimeMs) / 1000.0)
  )
  if ($qpcFrequency -lt 1000000 -or $qpcFrequency -gt 100000000) {
    throw "Derived QPC frequency is implausible: $qpcFrequency"
  }
  $qpcAtTraceOrigin = [double]$firstStage.Qpc -
    (($firstStage.TimeMs / 1000.0) * $qpcFrequency)

  $stageMap = New-FrameMap $stagePublishes 'StagePublish'
  $publicationMap = New-FrameMap $previewPublications 'PreviewPublication'
  $previewCallbackMap = New-FrameMap $previewCallbacks 'PreviewCallback'
  $textureCallbackMap = New-FrameMap `
    @($appEvents.TextureCallback) `
    'TextureCallback'
  $frameAvailableMap = New-FrameMap `
    @($appEvents.FrameAvailable) `
    'FrameAvailable'
  $advancedAcquireMap = New-FrameMap `
    @($appEvents.TextureAcquire | Where-Object Advanced) `
    'advanced TextureAcquire'
  $presentedCallbackMap = New-FrameMap `
    @($appEvents.FlutterFramePresented) `
    'FlutterFramePresented'

  $nonzeroWindowPresents = @(
    $decoder.DxgPresentEvents | Where-Object Hwnd -ne 0
  )
  if ($nonzeroWindowPresents.Count -eq 0) {
    throw "No nonzero-HWND DXGKRNL Present event was found for PID $ProcessId."
  }
  $windowGroups = @(
    $nonzeroWindowPresents |
      Group-Object Hwnd |
      Sort-Object Count -Descending
  )
  $mainWindowGroup = $windowGroups[0]
  $mainHwnd = [uint64]$mainWindowGroup.Group[0].Hwnd
  $mainPresents = @($mainWindowGroup.Group | Sort-Object TimeMs)

  $usedStageFrames = [Collections.Generic.HashSet[long]]::new()
  $stageCursor = -1
  $mainPresentLinks = [Collections.Generic.List[object]]::new()
  foreach ($present in $mainPresents) {
    while ($stageCursor + 1 -lt $stagePublishes.Count -and
           $stagePublishes[$stageCursor + 1].TimeMs -le $present.TimeMs) {
      $stageCursor++
    }

    $frameId = $null
    $reusedLatestFrame = $false
    if ($stageCursor -ge 0) {
      $candidateFrame = [long]$stagePublishes[$stageCursor].FrameId
      if ($usedStageFrames.Add($candidateFrame)) {
        $frameId = $candidateFrame
      } else {
        $reusedLatestFrame = $true
      }
    }

    $estimatedQpc = [long][math]::Round(
      $qpcAtTraceOrigin + (($present.TimeMs / 1000.0) * $qpcFrequency)
    )
    $mainPresentLinks.Add([pscustomobject]@{
      Present = $present
      EstimatedQpc = $estimatedQpc
      FrameId = $frameId
      ReusedLatestFrame = $reusedLatestFrame
    })
  }
  $mainPresentByFrame = @{}
  foreach ($link in $mainPresentLinks) {
    if ($null -ne $link.FrameId) {
      $mainPresentByFrame[[long]$link.FrameId] = $link
    }
  }

  $chains = [Collections.Generic.List[object]]::new()
  $orderViolationCount = 0
  foreach ($stage in $stagePublishes) {
    $frameId = [long]$stage.FrameId
    $publication = $publicationMap[$frameId]
    $previewCallback = $previewCallbackMap[$frameId]
    $textureCallback = $textureCallbackMap[$frameId]
    $frameAvailable = $frameAvailableMap[$frameId]
    $acquire = $advancedAcquireMap[$frameId]
    $presentedCallback = $presentedCallbackMap[$frameId]
    $dxgLink = $mainPresentByFrame[$frameId]

    $completeCustomChain =
      $null -ne $publication -and
      $null -ne $previewCallback -and
      $null -ne $textureCallback -and
      $null -ne $frameAvailable -and
      $null -ne $acquire -and
      $null -ne $presentedCallback
    $ordered = $completeCustomChain -and
      $stage.Qpc -le $publication.Qpc -and
      $publication.Qpc -le $previewCallback.Qpc -and
      $previewCallback.Qpc -le $textureCallback.Qpc -and
      $textureCallback.Qpc -le $frameAvailable.Qpc -and
      $frameAvailable.Qpc -le $acquire.Qpc -and
      $acquire.Qpc -le $presentedCallback.Qpc
    if ($completeCustomChain -and -not $ordered) {
      $orderViolationCount++
    }

    $chains.Add([pscustomobject]@{
      Generation = [long]$stage.Generation
      FrameId = $frameId
      StageTimeMs = [double]$stage.TimeMs
      StageQpc = [long]$stage.Qpc
      CompleteCustomChain = $completeCustomChain
      CustomChainOrdered = $ordered
      HasMainWindowPresent = $null -ne $dxgLink
      PublishToPublicationMs = if ($null -ne $publication) {
        Get-QpcDeltaMilliseconds $stage.Qpc $publication.Qpc $qpcFrequency
      } else { $null }
      PublicationToPreviewCallbackMs = if (
        $null -ne $publication -and $null -ne $previewCallback
      ) {
        Get-QpcDeltaMilliseconds `
          $publication.Qpc `
          $previewCallback.Qpc `
          $qpcFrequency
      } else { $null }
      PreviewToTextureCallbackMs = if (
        $null -ne $previewCallback -and $null -ne $textureCallback
      ) {
        Get-QpcDeltaMilliseconds `
          $previewCallback.Qpc `
          $textureCallback.Qpc `
          $qpcFrequency
      } else { $null }
      TextureCallbackToFrameAvailableMs = if (
        $null -ne $textureCallback -and $null -ne $frameAvailable
      ) {
        Get-QpcDeltaMilliseconds `
          $textureCallback.Qpc `
          $frameAvailable.Qpc `
          $qpcFrequency
      } else { $null }
      TextureCallbackToAcquireMs = if (
        $null -ne $textureCallback -and $null -ne $acquire
      ) {
        Get-QpcDeltaMilliseconds `
          $textureCallback.Qpc `
          $acquire.Qpc `
          $qpcFrequency
      } else { $null }
      AcquireToPresentedCallbackMs = if (
        $null -ne $acquire -and $null -ne $presentedCallback
      ) {
        Get-QpcDeltaMilliseconds `
          $acquire.Qpc `
          $presentedCallback.Qpc `
          $qpcFrequency
      } else { $null }
      PublishToPresentedCallbackMs = if ($null -ne $presentedCallback) {
        Get-QpcDeltaMilliseconds `
          $stage.Qpc `
          $presentedCallback.Qpc `
          $qpcFrequency
      } else { $null }
      PublishToDxgPresentMs = if ($null -ne $dxgLink) {
        Get-QpcDeltaMilliseconds `
          $stage.Qpc `
          $dxgLink.EstimatedQpc `
          $qpcFrequency
      } else { $null }
      AcquireToDxgPresentMs = if (
        $null -ne $acquire -and $null -ne $dxgLink
      ) {
        Get-QpcDeltaMilliseconds `
          $acquire.Qpc `
          $dxgLink.EstimatedQpc `
          $qpcFrequency
      } else { $null }
      PresentedCallbackToDxgPresentMs = if (
        $null -ne $presentedCallback -and $null -ne $dxgLink
      ) {
        Get-QpcDeltaMilliseconds `
          $presentedCallback.Qpc `
          $dxgLink.EstimatedQpc `
          $qpcFrequency
      } else { $null }
      Dropped = $null
      DxgPresentToDisplayedMs = $null
      PublishToDisplayedMs = $null
      DisplayQpc = $null
    })
  }
  $chainMap = New-FrameMap @($chains) 'analysis chain'

  $presentMon = $null
  $presentMonRows = @()
  $displayLinks = [Collections.Generic.List[object]]::new()
  if (-not [string]::IsNullOrWhiteSpace($PresentMonPath)) {
    $absolutePresentMon = Resolve-UnresolvedPath $PresentMonPath
    if (-not (Test-Path -LiteralPath $absolutePresentMon -PathType Leaf)) {
      throw "PresentMon does not exist: $absolutePresentMon"
    }

    Write-Host 'Resolving DWM displayed results with PresentMon...'
    & $absolutePresentMon `
      --etl_file $absoluteInput `
      --process_id $ProcessId `
      --output_file $presentMonCsv `
      --qpc_time `
      --v1_metrics `
      --no_console_stats
    if ($LASTEXITCODE -ne 0) {
      throw "PresentMon failed with exit code $LASTEXITCODE."
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $absolutePresentMon
    $presentMonFile = Get-Item -LiteralPath $absolutePresentMon
    $presentMon = [ordered]@{
      path = $absolutePresentMon
      fileVersion = $presentMonFile.VersionInfo.FileVersion
      sha256 = (Get-FileHash -LiteralPath $absolutePresentMon -Algorithm SHA256).Hash
      signatureStatus = $signature.Status.ToString()
      signer = if ($null -ne $signature.SignerCertificate) {
        $signature.SignerCertificate.Subject
      } else { $null }
    }

    $allPresentMonRows = @(Import-Csv -LiteralPath $presentMonCsv)
    $presentMonRows = @(
      $allPresentMonRows |
        Where-Object {
          $_.ProcessID -eq $ProcessId.ToString() -and
          $_.PresentMode -eq 'Composed: Copy with GPU GDI'
        } |
        Sort-Object { [long]$_.QPCTime }
    )

    $lastMainIndex = -1
    $maximumMatchTicks = [long][math]::Ceiling($qpcFrequency * 0.005)
    foreach ($row in $presentMonRows) {
      $rowQpc = [long]$row.QPCTime
      $candidateIndex = $lastMainIndex + 1
      if ($candidateIndex -ge $mainPresentLinks.Count) {
        break
      }
      while ($candidateIndex + 1 -lt $mainPresentLinks.Count) {
        $currentDelta = [math]::Abs(
          $mainPresentLinks[$candidateIndex].EstimatedQpc - $rowQpc
        )
        $nextDelta = [math]::Abs(
          $mainPresentLinks[$candidateIndex + 1].EstimatedQpc - $rowQpc
        )
        if ($nextDelta -gt $currentDelta) {
          break
        }
        $candidateIndex++
      }

      $mainLink = $mainPresentLinks[$candidateIndex]
      $matchDeltaTicks = [math]::Abs($mainLink.EstimatedQpc - $rowQpc)
      if ($matchDeltaTicks -gt $maximumMatchTicks) {
        continue
      }
      $lastMainIndex = $candidateIndex

      $dropped = $row.Dropped -eq '1'
      $displayQpc = if ($dropped) {
        $null
      } else {
        [long][math]::Round(
          $rowQpc + (([double]$row.msUntilDisplayed / 1000.0) * $qpcFrequency)
        )
      }
      $displayLinks.Add([pscustomobject]@{
        FrameId = $mainLink.FrameId
        StageTimeMs = if ($null -ne $mainLink.FrameId) {
          [double]$stageMap[[long]$mainLink.FrameId].TimeMs
        } else { $null }
        PresentMonQpc = $rowQpc
        DxgPresentQpc = [long]$mainLink.EstimatedQpc
        MatchDeltaMs = ($matchDeltaTicks * 1000.0) / $qpcFrequency
        Dropped = $dropped
        PresentToDisplayedMs = if ($dropped) {
          $null
        } else { [double]$row.msUntilDisplayed }
        DisplayQpc = $displayQpc
      })

      if ($null -ne $mainLink.FrameId) {
        $chain = $chainMap[[long]$mainLink.FrameId]
        $chain.Dropped = $dropped
        $chain.DxgPresentToDisplayedMs = if ($dropped) {
          $null
        } else {
          Get-QpcDeltaMilliseconds `
            $mainLink.EstimatedQpc `
            $displayQpc `
            $qpcFrequency
        }
        $chain.PublishToDisplayedMs = if ($dropped) {
          $null
        } else {
          Get-QpcDeltaMilliseconds `
            $chain.StageQpc `
            $displayQpc `
            $qpcFrequency
        }
        $chain.DisplayQpc = $displayQpc
      }
    }
  }

  $trimMilliseconds = $TrimEdgeSeconds * 1000.0
  $steadyStartMs = $firstStage.TimeMs + $trimMilliseconds
  $steadyEndMs = $lastStage.TimeMs - $trimMilliseconds
  $steadyChains = if ($steadyStartMs -le $steadyEndMs) {
    @($chains | Where-Object {
      $_.StageTimeMs -ge $steadyStartMs -and $_.StageTimeMs -le $steadyEndMs
    })
  } else { @() }

  $allStageIntervals = Get-Intervals $stagePublishes 'TimeMs'
  $steadyStagePublishes = @(
    $stagePublishes | Where-Object {
      $_.TimeMs -ge $steadyStartMs -and $_.TimeMs -le $steadyEndMs
    }
  )
  $steadyStageIntervals = Get-Intervals $steadyStagePublishes 'TimeMs'

  $displayedSteady = @(
    $displayLinks |
      Where-Object {
        -not $_.Dropped -and
        $null -ne $_.StageTimeMs -and
        $_.StageTimeMs -ge $steadyStartMs -and
        $_.StageTimeMs -le $steadyEndMs
      } |
      Sort-Object DisplayQpc
  )
  $displayIntervals = @()
  if ($displayedSteady.Count -gt 1) {
    $displayIntervals = @(
      for ($index = 1; $index -lt $displayedSteady.Count; $index++) {
        Get-QpcDeltaMilliseconds `
          $displayedSteady[$index - 1].DisplayQpc `
          $displayedSteady[$index].DisplayQpc `
          $qpcFrequency
      }
    )
  }

  $metricNames = @(
    'PublishToPublicationMs',
    'PublicationToPreviewCallbackMs',
    'PreviewToTextureCallbackMs',
    'TextureCallbackToFrameAvailableMs',
    'TextureCallbackToAcquireMs',
    'AcquireToPresentedCallbackMs',
    'PublishToPresentedCallbackMs',
    'PublishToDxgPresentMs',
    'AcquireToDxgPresentMs',
    'PresentedCallbackToDxgPresentMs',
    'DxgPresentToDisplayedMs',
    'PublishToDisplayedMs'
  )
  $allMetrics = [ordered]@{
    StagePublishIntervalMs = Get-Statistics $allStageIntervals
  }
  $steadyMetrics = [ordered]@{
    StagePublishIntervalMs = Get-Statistics $steadyStageIntervals
  }
  foreach ($metricName in $metricNames) {
    $allMetrics[$metricName] = Get-PropertyStatistics @($chains) $metricName
    $steadyMetrics[$metricName] = Get-PropertyStatistics `
      @($steadyChains) `
      $metricName
  }
  $steadyMetrics.DisplayedIntervalMs = Get-Statistics $displayIntervals

  $refreshHistogram = @()
  if ($RefreshRateHz -gt 0 -and $displayIntervals.Count -gt 0) {
    $refreshPeriodMs = 1000.0 / $RefreshRateHz
    $refreshHistogram = @(
      $displayIntervals |
        Group-Object { [math]::Round($_ / $refreshPeriodMs) } |
        Sort-Object { [int]$_.Name } |
        ForEach-Object {
          [ordered]@{
            refreshPeriods = [int]$_.Name
            approximateMilliseconds = [math]::Round(
              [int]$_.Name * $refreshPeriodMs,
              4
            )
            count = $_.Count
          }
        }
    )
  }

  $traceFile = Get-Item -LiteralPath $absoluteInput
  $mainContexts = @($mainPresents | Group-Object Context | Sort-Object Count -Descending)
  $mainThreads = @($mainPresents | Group-Object ThreadId | Sort-Object Count -Descending)
  $mainFlipIntervals = @(
    $mainPresents | Group-Object FlipInterval | Sort-Object Name | ForEach-Object {
      [ordered]@{ value = [int]$_.Name; count = $_.Count }
    }
  )
  $mainStatuses = @(
    $mainPresents | Group-Object ReturnStatus | Sort-Object Name | ForEach-Object {
      [ordered]@{ value = [int]$_.Name; count = $_.Count }
    }
  )
  $presentMonModeCounts = @()
  if ($null -ne $presentMon) {
    $presentMonModeCounts = @(
      Import-Csv -LiteralPath $presentMonCsv |
        Group-Object PresentMode,Dropped |
        Sort-Object Name |
        ForEach-Object {
          [ordered]@{ key = $_.Name; count = $_.Count }
      }
    )
  }
  $displayFrameIds = @(
    $displayLinks |
      Where-Object { $null -ne $_.FrameId } |
      ForEach-Object { [long]$_.FrameId }
  )
  $displayFrameSet = [Collections.Generic.HashSet[long]]::new()
  foreach ($frameId in $displayFrameIds) {
    [void]$displayFrameSet.Add($frameId)
  }
  $mainFramesWithoutPresentMon = @(
    $mainPresentLinks |
      Where-Object {
        $null -ne $_.FrameId -and
        -not $displayFrameSet.Contains([long]$_.FrameId)
      } |
      ForEach-Object { [long]$_.FrameId }
  )
  $droppedFrameIds = @(
    $displayLinks |
      Where-Object { $_.Dropped -and $null -ne $_.FrameId } |
      ForEach-Object { [long]$_.FrameId }
  )

  $report = [ordered]@{
    schemaVersion = 1
    scenario = $Scenario
    generatedAt = [DateTimeOffset]::Now.ToString('o')
    sourceTrace = [ordered]@{
      path = $absoluteInput
      bytes = $traceFile.Length
      sha256 = (Get-FileHash -LiteralPath $absoluteInput -Algorithm SHA256).Hash
      processId = $ProcessId
    }
    tools = [ordered]@{
      powerShell = $PSVersionTable.PSVersion.ToString()
      xperf = [Diagnostics.FileVersionInfo]::GetVersionInfo($xperf).FileVersion
      traceProcessingAssembly = [Reflection.AssemblyName]::GetAssemblyName(
        $processingAssembly
      ).Version.ToString()
      presentMon = $presentMon
    }
    timing = [ordered]@{
      derivedQpcFrequency = $qpcFrequency
      trimEdgeSeconds = $TrimEdgeSeconds
      steadyStartMs = [math]::Round($steadyStartMs, 4)
      steadyEndMs = [math]::Round($steadyEndMs, 4)
    }
    window = [ordered]@{
      hwnd = ('0x{0:x}' -f $mainHwnd)
      nonzeroHwndCount = $windowGroups.Count
      dominantContext = if ($mainContexts.Count -gt 0) {
        '0x{0:x}' -f [uint32]$mainContexts[0].Group[0].Context
      } else { $null }
      dominantThreadId = if ($mainThreads.Count -gt 0) {
        [int]$mainThreads[0].Group[0].ThreadId
      } else { $null }
      flipIntervals = $mainFlipIntervals
      returnStatuses = $mainStatuses
    }
    counts = [ordered]@{
      nativeStageProviderEvents = $decoder.NativeStageProviderEvents
      dxgKrnlProviderEvents = $decoder.DxgKrnlProviderEvents
      malformedNativeStageEvents = $decoder.MalformedNativeStageEvents
      malformedDxgPresentEvents = $decoder.MalformedDxgPresentEvents
      stagePublish = $stagePublishes.Count
      previewPublication = $previewPublications.Count
      previewCallback = $previewCallbacks.Count
      textureCallback = $appEvents.TextureCallback.Count
      frameAvailable = $appEvents.FrameAvailable.Count
      textureAcquire = $appEvents.TextureAcquire.Count
      advancedTextureAcquire = @(
        $appEvents.TextureAcquire | Where-Object Advanced
      ).Count
      repeatedTextureAcquire = @(
        $appEvents.TextureAcquire | Where-Object { -not $_.Advanced }
      ).Count
      flutterFramePresentedCallback = $appEvents.FlutterFramePresented.Count
      completeCustomChains = @($chains | Where-Object CompleteCustomChain).Count
      customChainOrderViolations = $orderViolationCount
      mainWindowDxgPresent = $mainPresents.Count
      stageFramesWithMainWindowDxgPresent = @(
        $chains | Where-Object HasMainWindowPresent
      ).Count
      dxgPresentReusingLatestStageFrame = @(
        $mainPresentLinks | Where-Object ReusedLatestFrame
      ).Count
      presentMonCopyGpuGdi = $presentMonRows.Count
      presentMonMatchedToMainWindow = $displayLinks.Count
      mainWindowDxgPresentWithoutPresentMon =
        $mainPresents.Count - $displayLinks.Count
      presentMonPresented = @($displayLinks | Where-Object { -not $_.Dropped }).Count
      presentMonDropped = @($displayLinks | Where-Object Dropped).Count
      steadyFrames = $steadyChains.Count
      steadyPresented = @(
        $steadyChains | Where-Object { $_.Dropped -eq $false }
      ).Count
      steadyDropped = @(
        $steadyChains | Where-Object { $_.Dropped -eq $true }
      ).Count
    }
    frameRange = [ordered]@{
      generation = [long]$firstStage.Generation
      first = [long]$firstStage.FrameId
      last = [long]$lastStage.FrameId
    }
    presentMonModeCounts = $presentMonModeCounts
    presentMonPairing = [ordered]@{
      matchDeltaMilliseconds = Get-PropertyStatistics `
        @($displayLinks) `
        'MatchDeltaMs'
      mainWindowFramesWithoutPresentMon = $mainFramesWithoutPresentMon
      droppedFrameIds = $droppedFrameIds
    }
    allMetricsMilliseconds = $allMetrics
    steadyMetricsMilliseconds = $steadyMetrics
    displayCadence = [ordered]@{
      refreshRateHz = if ($RefreshRateHz -gt 0) { $RefreshRateHz } else { $null }
      refreshPeriodHistogram = $refreshHistogram
    }
    notes = @(
      'FlutterFramePresented is a stock embedder callback dispatched after SwapBuffers; it is not the kernel Present timestamp.',
      'PresentMon can omit initial events while its offline tracking reaches a reliable state; counts preserve that warm-up gap.',
      'A high-refresh sample is causal and timing evidence, not proof of target 60 Hz visual smoothness.'
    )
  }

  $json = $report | ConvertTo-Json -Depth 12
  [IO.File]::WriteAllText(
    $absoluteReport,
    $json + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
  )

  Write-Host "Trace SHA-256: $($report.sourceTrace.sha256)"
  Write-Host "Stage publishes: $($report.counts.stagePublish)"
  Write-Host "Main-window DXG presents: $($report.counts.mainWindowDxgPresent)"
  if ($null -ne $presentMon) {
    Write-Host (
      'PresentMon displayed/dropped: ' +
      "$($report.counts.presentMonPresented)/$($report.counts.presentMonDropped)"
    )
    Write-Host (
      'Steady displayed/dropped: ' +
      "$($report.counts.steadyPresented)/$($report.counts.steadyDropped)"
    )
  }
  Write-Host "Report saved to $absoluteReport"
} finally {
  if (Test-Path -LiteralPath $appEventDump) {
    [IO.File]::Delete($appEventDump)
  }
  if (Test-Path -LiteralPath $presentMonCsv) {
    [IO.File]::Delete($presentMonCsv)
  }
  if (Test-Path -LiteralPath $temporaryDirectory) {
    [IO.Directory]::Delete($temporaryDirectory, $false)
  }
}
