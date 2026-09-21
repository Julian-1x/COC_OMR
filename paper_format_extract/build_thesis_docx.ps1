# Build COC OMR Chapters 1-4 DOCX matching measured Ch1-3 format.
# Format source: paper_format_extract/FORMAT_SPEC.md

$ErrorActionPreference = 'Stop'
$outPath = 'd:\omr_app\COC_OMR_Chapters_1_4_REVISED.docx'
$md13 = Get-Content -Raw 'd:\omr_app\paper_format_extract\chapter1_3_camera_ready.md'
$md4  = Get-Content -Raw 'd:\omr_app\paper_format_extract\chapter4_camera_ready.md'
$md = ($md13.TrimEnd() + "`r`n`r`n" + $md4.TrimStart())

# Word constants
$wdAlignParagraphLeft = 0
$wdAlignParagraphCenter = 1
$wdAlignParagraphJustify = 3
$wdAlignParagraphRight = 2
$wdLineSpaceExactly = 4
$wdTrailingTab = 2
$wdCollapseEnd = 0
$wdHeaderFooterPrimary = 1
$wdSeekMainDocument = 0
$wdSeekCurrentPageHeader = 9
$wdSeekCurrentPageFooter = 10
$wdFieldEmpty = -1
$wdFieldPage = 33
$wdBorderTop = 1
$wdBorderLeft = 2
$wdBorderBottom = 3
$wdBorderRight = 4
$wdBorderHorizontal = 8
$wdBorderVertical = 9
$wdLineStyleSingle = 1
$wdLineWidth050pt = 4
$wdAutoFitWindow = 2
$wdStory = 6

function Clean-Md([string]$s) {
  if ($null -eq $s) { return '' }
  # strip markdown bold/italic/code without deleting surrounding text
  while ($s -match '\*\*(.+?)\*\*') { $s = $s.Replace($Matches[0], $Matches[1]) }
  while ($s -match '(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)') { $s = $s.Replace($Matches[0], $Matches[1]) }
  $s = $s -replace '`([^`]+)`', '$1'
  $s = $s -replace '^\>\s*', ''
  return $s.Trim()
}

function Set-BodyPara($para, [bool]$indent = $true) {
  $pf = $para.Format
  $pf.Alignment = $wdAlignParagraphLeft
  $pf.LineSpacingRule = $wdLineSpaceExactly
  $pf.LineSpacing = 27.6
  $pf.SpaceBefore = 0
  $pf.SpaceAfter = 0
  if ($indent) {
    $pf.FirstLineIndent = 36
  } else {
    $pf.FirstLineIndent = 0
  }
  $pf.LeftIndent = 0
  $f = $para.Range.Font
  $f.Name = 'Times New Roman'
  $f.Size = 12
  $f.Bold = $false
  $f.Italic = $false
}

function Write-Styled([string]$text, [string]$kind) {
  $sel = $script:word.Selection
  $start = $sel.Start
  $sel.TypeText($text)
  $end = $sel.Start
  $rng = $script:doc.Range($start, $end)
  $para = $rng.Paragraphs.Item(1)
  $pf = $para.Format
  $f = $rng.Font

  $pf.LineSpacingRule = $wdLineSpaceExactly
  $pf.LineSpacing = 27.6
  $pf.SpaceBefore = 0
  $pf.SpaceAfter = 0
  $pf.LeftIndent = 0
  $pf.FirstLineIndent = 0
  $f.Name = 'Times New Roman'
  $f.Size = 12
  $f.Bold = $false
  $f.Italic = $false

  switch ($kind) {
    'CHAPTER' {
      $pf.Alignment = $wdAlignParagraphCenter
      $f.Bold = $true
    }
    'CHAPTER_TITLE' {
      $pf.Alignment = $wdAlignParagraphCenter
      $f.Bold = $true
    }
    'H1' {
      $pf.Alignment = $wdAlignParagraphLeft
      $pf.SpaceBefore = 12
      $f.Bold = $true
    }
    'H2' {
      $pf.Alignment = $wdAlignParagraphLeft
      $pf.SpaceBefore = 12
      $f.Bold = $true
    }
    'CAPTION' {
      $pf.Alignment = $wdAlignParagraphCenter
      $pf.SpaceBefore = 6
      $pf.SpaceAfter = 6
      $f.Name = 'Arial'
      $f.Size = 11
    }
    'BODY' {
      $pf.Alignment = $wdAlignParagraphLeft
      $pf.FirstLineIndent = 36
    }
    'BODY_NOINDENT' {
      $pf.Alignment = $wdAlignParagraphLeft
      $pf.FirstLineIndent = 0
    }
    'LIST' {
      $pf.Alignment = $wdAlignParagraphLeft
      $pf.LeftIndent = 18
      $pf.FirstLineIndent = 0
    }
  }
  $sel.TypeParagraph()
}

function Insert-Table([string[]]$rows) {
  $parsed = @()
  foreach ($r in $rows) {
    $cells = @($r.Trim().Trim('|') -split '\|' | ForEach-Object { (Clean-Md $_.Trim()) })
    if (($cells -join '') -match '^[\s:\-]+$') { continue }
    $parsed += ,$cells
  }
  if ($parsed.Count -lt 1) { return }
  $cols = ($parsed | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
  $sel = $script:word.Selection
  # ensure selection is a collapsed insertion point
  $sel.Collapse(1) | Out-Null
  $table = $script:doc.Tables.Add($sel.Range, $parsed.Count, $cols)
  try { $table.Style = 'Table Grid' } catch {}
  try { $table.AutoFitBehavior($wdAutoFitWindow) } catch {}
  foreach ($b in @($wdBorderTop,$wdBorderLeft,$wdBorderBottom,$wdBorderRight,$wdBorderHorizontal,$wdBorderVertical)) {
    try {
      $table.Borders.Item($b).LineStyle = $wdLineStyleSingle
      $table.Borders.Item($b).LineWidth = $wdLineWidth050pt
    } catch {}
  }
  for ($ri = 0; $ri -lt $parsed.Count; $ri++) {
    for ($j = 0; $j -lt $cols; $j++) {
      $txt = if ($j -lt $parsed[$ri].Count) { $parsed[$ri][$j] } else { '' }
      $cell = $table.Cell($ri + 1, $j + 1)
      $cell.Range.Text = $txt
      # remove end-of-cell marker formatting issues by trimming paragraph mark text side effects
      $cell.Range.Font.Name = 'Times New Roman'
      $cell.Range.Font.Size = 12
      $cell.Range.Font.Bold = ($ri -eq 0)
      $cell.Range.ParagraphFormat.LineSpacingRule = $wdLineSpaceExactly
      $cell.Range.ParagraphFormat.LineSpacing = 14
      $cell.Range.ParagraphFormat.SpaceBefore = 2
      $cell.Range.ParagraphFormat.SpaceAfter = 2
      $cell.Range.ParagraphFormat.FirstLineIndent = 0
      $cell.Range.ParagraphFormat.Alignment = $wdAlignParagraphLeft
    }
  }
  $end = $table.Range
  $end.Collapse(0) | Out-Null
  $end.Select()
  $script:word.Selection.MoveRight(1, 1) | Out-Null
  $script:word.Selection.TypeParagraph()
}

# --- Start Word ---
Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
$doc = $word.Documents.Add()
$script:word = $word
$script:doc = $doc

# Page setup A4, 1" margins
$ps = $doc.PageSetup
$ps.PageWidth = 595.35
$ps.PageHeight = 841.9
$ps.TopMargin = 72
$ps.BottomMargin = 72
$ps.LeftMargin = 72
$ps.RightMargin = 72
$ps.HeaderDistance = 36
$ps.FooterDistance = 36

# Default style
$normal = $doc.Styles.Item('Normal')
$normal.Font.Name = 'Times New Roman'
$normal.Font.Size = 12
$normal.ParagraphFormat.LineSpacingRule = $wdLineSpaceExactly
$normal.ParagraphFormat.LineSpacing = 27.6
$normal.ParagraphFormat.SpaceBefore = 0
$normal.ParagraphFormat.SpaceAfter = 0

# Header
$sec = $doc.Sections.Item(1)
$hdr = $sec.Headers.Item($wdHeaderFooterPrimary)
$hdr.Range.Text = 'Cagayan de Oro College | College of Information Technology Education'
$hdr.Range.Font.Name = 'Times New Roman'
$hdr.Range.Font.Size = 12
$hdr.Range.Font.Bold = $true
$hdr.Range.ParagraphFormat.Alignment = $wdAlignParagraphLeft
$hdr.Range.ParagraphFormat.FirstLineIndent = 0
$hdr.Range.ParagraphFormat.LineSpacingRule = $wdLineSpaceExactly
$hdr.Range.ParagraphFormat.LineSpacing = 14

# Footer page number centered
$ftr = $sec.Footers.Item($wdHeaderFooterPrimary)
$ftr.Range.Delete() | Out-Null
$ftr.Range.ParagraphFormat.Alignment = $wdAlignParagraphCenter
$ftr.Range.Font.Name = 'Times New Roman'
$ftr.Range.Font.Size = 12
$ftr.Range.Font.Bold = $false
$ftr.Range.Fields.Add($ftr.Range, $wdFieldPage) | Out-Null

$script:inTable = $false
$script:tableBuf = @()

# Parse markdown lines
$lines = $md -split "`r`n|\n|\r"
$i = 0
$chapterStarted = $false

function Flush-Table {
  if ($script:tableBuf.Count -gt 0) {
    Insert-Table $script:tableBuf
    $script:tableBuf = @()
  }
  $script:inTable = $false
}

while ($i -lt $lines.Count) {
  $raw = $lines[$i]
  $line = $raw.TrimEnd()

  # Table lines
  if ($line -match '^\|') {
    $script:inTable = $true
    $script:tableBuf += $line
    $i++
    continue
  } elseif ($script:inTable) {
    Flush-Table
  }

  if ([string]::IsNullOrWhiteSpace($line) -or $line -eq '---') {
    $i++; continue
  }

  # Skip meta-ish leftover lines
  if ($line -match '^Replace every' -or $line -match '^Forbidden:' -or $line -match '^\*\*Format source') {
    $i++; continue
  }

  if ($line -match '^# CHAPTER\s+(\d+)\s*$') {
    if ($chapterStarted) {
      $word.Selection.InsertBreak(7) | Out-Null # wdPageBreak
    }
    $chapterStarted = $true
    Write-Styled ("CHAPTER " + $Matches[1]) 'CHAPTER'
    $i++; continue
  }

  if ($line -match '^# CHAPTER\s+(\d+)\s*$') { }

  if ($line -match '^##\s+(.+)$') {
    $title = Clean-Md $Matches[1]
    # Chapter title ALL CAPS style when it's THE PROBLEM / METHODOLOGY / etc.
    if ($title -cmatch '^(THE PROBLEM|REVIEW OF RELATED LITERATURE AND STUDIES|METHODOLOGY|PRESENTATION, ANALYSIS, AND INTERPRETATION OF DATA)$' -or $title -eq $title.ToUpper()) {
      Write-Styled $title.ToUpper() 'CHAPTER_TITLE'
    } elseif ($title -match '^REFERENCES$') {
      $word.Selection.InsertBreak(7) | Out-Null
      Write-Styled 'REFERENCES' 'CHAPTER_TITLE'
    } else {
      Write-Styled $title 'H1'
    }
    $i++; continue
  }

  if ($line -match '^###\s+(.+)$') {
    Write-Styled (Clean-Md $Matches[1]) 'H1'
    $i++; continue
  }

  if ($line -match '^####\s+(.+)$') {
    Write-Styled (Clean-Md $Matches[1]) 'H2'
    $i++; continue
  }

  if ($line -match '^\*\*Figure\s+.+\*\*' -or $line -match '^Figure\s+[\d\.]') {
    Write-Styled (Clean-Md $line) 'CAPTION'
    $i++; continue
  }

  # Standalone bold label lines (e.g. **General Objective**)
  if ($line -match '^\*\*[^*]+\*\*\s*$') {
    Write-Styled (Clean-Md $line) 'H2'
    $i++; continue
  }

  if ($line -match '^\*\s+(.+)$' -or $line -match '^-\s+(.+)$') {
    $item = Clean-Md $Matches[1]
    Write-Styled ("• " + $item) 'LIST'
    $i++; continue
  }

  if ($line -match '^(\d+)\.\s+(.+)$') {
    Write-Styled ("$($Matches[1]). " + (Clean-Md $Matches[2])) 'LIST'
    $i++; continue
  }

  if ($line -match '^>\s*(.+)$') {
    Write-Styled (Clean-Md $Matches[1]) 'BODY'
    $i++; continue
  }

  # Default paragraph (may be multi-line joined? treat each non-empty as para)
  Write-Styled (Clean-Md $line) 'BODY'
  $i++
}
Flush-Table

# Save
if (Test-Path $outPath) { Remove-Item $outPath -Force }
$doc.SaveAs2([ref]$outPath, [ref]16) | Out-Null
$pages = $doc.ComputeStatistics(2)
$tables = $doc.Tables.Count
$paras = $doc.Paragraphs.Count
$doc.Close($false)
$word.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
[GC]::Collect()
Write-Output "SAVED $outPath"
Write-Output "pages=$pages tables=$tables paras=$paras"
Get-Item $outPath | Format-List FullName, Length, LastWriteTime
