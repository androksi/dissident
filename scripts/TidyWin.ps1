#Requires -RunAsAdministrator
<#
    TidyWin.ps1 — the TidyWin panel: a window with every option. Each option runs its script and shows
    the script's questions and progress in the window.

    HOW TO RUN:
        irm androksi.github.io/tidywin/run | iex          (the launcher asks for administrator rights)
    or from a copy of the repository (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -STA -File .\scripts\TidyWin.ps1

    HOW IT WORKS
        Each option runs its script in a separate Windows PowerShell process with $env:TIDYWIN_PANEL = 1.
        What the script writes shows in the log. Its questions arrive as "##TIDYWIN {json}" lines and show
        as a card above the log; the answer goes back on the script's standard input (see the PANEL region
        in any script). Scripts come from the copy next to this file (a copy of the repository) or are
        downloaded from the site every time.

    To add an option: one entry in Get-Menu (section 1).

    FILE LAYOUT
        1. Menu items
        2. Look: colors, logo and window
        3. Running a script
        4. Log
        5. Question cards
        6. Option pages
        7. Pages
        8. Start
#>
param(
    [string]$Base = 'https://androksi.github.io/tidywin'      # where the scripts are published (GitHub Pages)
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).'
    return
}
# WPF windows need a single-threaded apartment (the default of powershell.exe, but not of every host)
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $PSCommandPath -Base $Base
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms


#region ==================== 1. MENU ITEMS ====================

# One script to run: path under scripts/, its arguments and a name (shown when an option has several steps).
function New-Step($Script, $ScriptArgs, $Name) {
    [pscustomobject]@{ Script = $Script; Args = @($ScriptArgs | Where-Object { $_ }); Name = $Name }
}

# Group, id (the name used on the site), icon (Segoe Fluent Icons code), name in the sidebar, page title,
# one-line description, what it does (points), the start button and the scripts it runs.
# -Form: the page shows every option of the script (it supports -Describe and -Answers) instead of the points.
function New-MenuEntry($Group, $Id, $Icon, $Name, $Title, $Desc, [string[]]$Points, $Action, [object[]]$Steps, [switch]$Form) {
    [pscustomobject]@{
        Group = $Group; Id = $Id; Icon = [string][char][Convert]::ToInt32($Icon, 16); Name = $Name; Title = $Title
        Desc = $Desc; Points = $Points; Action = $Action; Steps = $Steps; Form = [bool]$Form
    }
}

function Get-Menu {
    $setup = 'Set up'; $care = 'Maintenance'; $format = 'Formatting the PC'; $undo = 'Undo'
    @(
        New-MenuEntry $setup 'windows' 'E770' 'Windows' 'Windows' 'Clean up Windows and set it up the way you like.' @(
            'Turns off telemetry, ads and suggestions.'
            'Removes the preinstalled apps you pick, and OneDrive if you want.'
            'Sets the theme, taskbar, File Explorer, screen and power.'
            'Creates a restore point first and saves a log on your Desktop.'
        ) 'Start' @(New-Step 'windows/configure-windows.ps1') -Form

        New-MenuEntry $setup 'apps' 'E71D' 'Applications' 'Applications' 'Install the apps you use, all at once.' @(
            'Pick from 105 apps: browsers, games, media, development and more.'
            'Installs them from their official sources with WinGet.'
            'Apps you already have are marked.'
        ) 'Choose apps' @(New-Step 'apps/configure-apps.ps1') -Form

        New-MenuEntry $setup 'fonts' 'E8D2' 'Fonts' 'Fonts' 'Install fonts for code, the terminal and documents.' @(
            'Pick from 19 free fonts, like JetBrains Mono, Fira Code and Inter.'
            'Downloads them from their official sources.'
            'Installs them for every user. Undo removes only these.'
        ) 'Choose fonts' @(New-Step 'fonts/install-fonts.ps1') -Form

        # One page for the three browsers: a switch for each, its options under it (each script describes its own)
        New-MenuEntry $setup 'browsers' 'E774' 'Browsers' 'Browsers' 'Make Chrome, Brave and Firefox more private.' @(
            'Turn on a browser to see its options.'
        ) 'Start' @((New-Step 'browsers/configure-chrome.ps1' $null 'Chrome'), (New-Step 'browsers/configure-brave.ps1' $null 'Brave'), (New-Step 'browsers/configure-firefox.ps1' $null 'Firefox')) -Form


        New-MenuEntry $care 'uninstall' 'E74D' 'Uninstall programs' 'Uninstall programs' 'Remove programs and what they leave behind.' @(
            'Runs the official uninstaller of each program you pick.'
            'Then lists the leftover folders, registry keys and shortcuts.'
            'Deletes only what you confirm: folders go to the Recycle Bin and registry keys are backed up.'
        ) 'Uninstall' @(New-Step 'apps/uninstall-apps.ps1') -Form

        New-MenuEntry $care 'cleanup' 'EDA2' 'Free up disk space' 'Free up disk space' 'Delete files Windows doesn''t need.' @(
            'Temporary files, old update downloads, error reports and more.'
            'Shows the size of each and asks before deleting it.'
        ) 'Clean' @(New-Step 'windows/clean-windows.ps1') -Form

        New-MenuEntry $care 'repair' 'E90F' 'Repair Windows' 'Repair Windows' 'Fix Windows when it acts strange.' @(
            'Checks and repairs the system files with Windows'' own tools.'
            'Checks the disk for errors.'
            'Creates a restore point first. Takes 10 to 30 minutes.'
        ) 'Repair' @(New-Step 'windows/repair-windows.ps1') -Form

        New-MenuEntry $care 'network-reset' 'E701' 'Network' 'Network' 'Fix "connected, no internet" and sites that don''t load.' @(
            'Quick: clears the caches and gets a new IP. No restart.'
            'Full: also resets the Windows network settings. Needs a restart.'
            'Your DNS settings stay.'
        ) 'Reset' @(New-Step 'windows/reset-network.ps1') -Form

        # Backup: apps, then drivers. Restore: drivers first (network, video), then the apps, which need the internet.
        New-MenuEntry $format 'backup' 'E74E' 'Back up apps and drivers' 'Back up apps and drivers' 'Save your apps and drivers before formatting.' @(
            'Saves the list of your installed apps.'
            'Saves the drivers you pick.'
            'Save them to a USB drive or another disk.'
        ) 'Back up' @((New-Step 'apps/backup-apps.ps1' '-Export' 'App list'), (New-Step 'drivers/backup-drivers.ps1' '-Export' 'Drivers')) -Form

        New-MenuEntry $format 'restore' 'E896' 'Restore apps and drivers' 'Restore apps and drivers' 'Put your apps and drivers back after formatting.' @(
            'Installs the saved drivers Windows didn''t install by itself.'
            'Then installs your saved apps.'
            'Run it after Windows Update has finished.'
        ) 'Restore' @((New-Step 'drivers/backup-drivers.ps1' '-Import' 'Drivers'), (New-Step 'apps/backup-apps.ps1' '-Import' 'App list')) -Form

        New-MenuEntry $undo 'windows-revert' 'E7A7' 'Windows' 'Undo Windows' 'Pick what to put back the way Windows had it.' @(
            'Telemetry, suggestions, File Explorer, DNS and the other settings, one by one.'
        ) 'Undo' @(New-Step 'windows/revert-configure-windows.ps1') -Form

        New-MenuEntry $undo 'chrome-revert' 'E7A7' 'Chrome' 'Undo Chrome' 'Pick which TidyWin settings to remove from Chrome.' @(
            'Only the settings that are on this PC show up.'
        ) 'Undo' @(New-Step 'browsers/configure-chrome.ps1' '-Revert') -Form

        New-MenuEntry $undo 'brave-revert' 'E7A7' 'Brave' 'Undo Brave' 'Pick which TidyWin settings to remove from Brave.' @(
            'Only the settings that are on this PC show up.'
        ) 'Undo' @(New-Step 'browsers/configure-brave.ps1' '-Revert') -Form

        New-MenuEntry $undo 'firefox-revert' 'E7A7' 'Firefox' 'Undo Firefox' 'Pick which TidyWin settings to remove from Firefox.' @(
            'Only the settings that are on this PC show up.'
        ) 'Undo' @(New-Step 'browsers/configure-firefox.ps1' '-Revert') -Form

        New-MenuEntry $undo 'fonts-revert' 'E7A7' 'Fonts' 'Undo fonts' 'Pick which of the fonts TidyWin installed to remove.' @(
            'Fonts you installed another way stay.'
        ) 'Undo' @(New-Step 'fonts/install-fonts.ps1' '-Revert') -Form
    ) | Where-Object Group -ne $format     # Formatting the PC: hidden for now, while its pages are rethought
}

#endregion


#region ==================== 2. LOOK: COLORS, LOGO AND WINDOW ====================

# Light or dark like Windows' apps, with the Windows accent color.
function Get-Theme {
    $light = $true
    try { $light = (Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' -ErrorAction Stop) -ne 0 } catch { }
    $t = if ($light) {
        @{ WinBg = '#F3F3F3'; PageBg = '#F9F9F9'; Card = '#FFFFFF'; Line = '#E5E5E5'; Fg = '#1B1B1B'; Fg2 = '#5C5C5C'; Fg3 = '#8A8A8A'
           Hover = '#0A000000'; Selected = '#10000000'; Control = '#FFFFFF'; ControlLine = '#D4D4D4'; ControlStrong = '#8A8A8A'
           LogBg = '#FFFFFF'; Ok = '#0F7B0F'; Warn = '#9D5D00'; Err = '#C42B1C'; Accent = '#005FB8'; OnAccent = '#FFFFFF' }
    } else {
        @{ WinBg = '#202020'; PageBg = '#272727'; Card = '#2D2D2D'; Line = '#383838'; Fg = '#FFFFFF'; Fg2 = '#C5C5C5'; Fg3 = '#9A9A9A'
           Hover = '#0FFFFFFF'; Selected = '#17FFFFFF'; Control = '#333333'; ControlLine = '#454545'; ControlStrong = '#A0A0A0'
           LogBg = '#1E1E1E'; Ok = '#6CCB5F'; Warn = '#FCE100'; Err = '#FF99A4'; Accent = '#60CDFF'; OnAccent = '#000000' }
    }
    try {
        # Windows uses a darker shade of the accent on light, a lighter one on dark
        $p = [byte[]](Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' 'AccentPalette' -ErrorAction Stop)
        $i = if ($light) { 4 } else { 1 }
        if ($p.Count -ge 32) { $t.Accent = '#{0:X2}{1:X2}{2:X2}' -f $p[$i * 4], $p[$i * 4 + 1], $p[$i * 4 + 2] }
    } catch { }
    $t.Light = $light
    return $t
}

# The TidyWin logo (assets/logo.svg: a closed window, four panes with the shutters drawn) as an image.
function New-Logo([int]$Size) {
    $brush = { param($hex) $b = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($hex)); $b.Freeze(); $b }
    $dark = & $brush '#0D1117'; $light = & $brush '#E6EDF3'
    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $dc.PushTransform((New-Object Windows.Media.ScaleTransform ($Size / 160), ($Size / 160)))
    $dc.DrawRoundedRectangle($dark, (New-Object Windows.Media.Pen (& $brush '#30363D'), 2), (New-Object Windows.Rect 8, 8, 144, 144), 18, 18)
    $slat = New-Object Windows.Media.Pen $dark, 3
    $slat.StartLineCap = 'Round'; $slat.EndLineCap = 'Round'
    foreach ($x in 30, 84) {
        foreach ($y in 30, 84) {
            $dc.DrawRoundedRectangle($light, $null, (New-Object Windows.Rect $x, $y, 46, 46), 4, 4)
            foreach ($dy in 12, 23, 34) { $dc.DrawLine($slat, (New-Object Windows.Point ($x + 6), ($y + $dy)), (New-Object Windows.Point ($x + 40), ($y + $dy))) }
        }
    }
    $dc.DrawEllipse($dark, (New-Object Windows.Media.Pen $light, 3), (New-Object Windows.Point 80, 80), 9, 9)
    $dc.DrawRoundedRectangle($light, $null, (New-Object Windows.Rect 78, 76, 4, 8), 1, 1)
    $dc.Pop(); $dc.Close()
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap $Size, $Size, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dv)
    $bmp.Freeze()
    return $bmp
}

$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TidyWin" Width="1080" Height="740" MinWidth="820" MinHeight="520"
        WindowStartupLocation="CenterScreen" Background="%WinBg%" Foreground="%Fg%"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" UseLayoutRounding="False" SnapsToDevicePixels="True">
  <Window.Resources>
    <SolidColorBrush x:Key="WinBg" Color="%WinBg%"/>
    <SolidColorBrush x:Key="PageBg" Color="%PageBg%"/>
    <SolidColorBrush x:Key="Card" Color="%Card%"/>
    <SolidColorBrush x:Key="Line" Color="%Line%"/>
    <SolidColorBrush x:Key="Fg" Color="%Fg%"/>
    <SolidColorBrush x:Key="Fg2" Color="%Fg2%"/>
    <SolidColorBrush x:Key="Fg3" Color="%Fg3%"/>
    <SolidColorBrush x:Key="Hover" Color="%Hover%"/>
    <SolidColorBrush x:Key="Selected" Color="%Selected%"/>
    <SolidColorBrush x:Key="Control" Color="%Control%"/>
    <SolidColorBrush x:Key="ControlLine" Color="%ControlLine%"/>
    <SolidColorBrush x:Key="ControlStrong" Color="%ControlStrong%"/>
    <SolidColorBrush x:Key="LogBg" Color="%LogBg%"/>
    <SolidColorBrush x:Key="Ok" Color="%Ok%"/>
    <SolidColorBrush x:Key="Warn" Color="%Warn%"/>
    <SolidColorBrush x:Key="Err" Color="%Err%"/>
    <SolidColorBrush x:Key="Accent" Color="%Accent%"/>
    <SolidColorBrush x:Key="OnAccent" Color="%OnAccent%"/>

    <!-- Sidebar item: Tag="on" when its page is open -->
    <Style x:Key="Nav" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="Transparent" CornerRadius="5" Margin="0,1" Padding="12,8" BorderThickness="1" BorderBrush="Transparent">
              <Grid>
                <Border x:Name="Pill" Width="3" Height="16" CornerRadius="1.5" Background="{StaticResource Accent}" HorizontalAlignment="Left" Margin="-13,0,0,0" Visibility="Collapsed"/>
                <ContentPresenter/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="{StaticResource Hover}"/></Trigger>
              <Trigger Property="Tag" Value="on">
                <Setter TargetName="B" Property="Background" Value="{StaticResource Selected}"/>
                <Setter TargetName="Pill" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="{StaticResource Fg}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Buttons: Btn (normal) and Primary (accent) -->
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Background" Value="{StaticResource Control}"/>
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="BorderBrush" Value="{StaticResource ControlLine}"/>
      <Setter Property="Padding" Value="18,6"/>
      <Setter Property="MinWidth" Value="96"/>
      <Setter Property="MinHeight" Value="32"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="4"/>
              <Border x:Name="H" Background="{StaticResource Fg}" Opacity="0" CornerRadius="4"/>
              <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="H" Property="Opacity" Value="0.06"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="H" Property="Opacity" Value="0.12"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="{StaticResource Fg}"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="{StaticResource Accent}"/>
      <Setter Property="Foreground" Value="{StaticResource OnAccent}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Accent}"/>
    </Style>
    <Style x:Key="Link" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Accent}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <TextBlock x:Name="T" Text="{TemplateBinding Content}" Background="Transparent"/>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="T" Property="TextDecorations" Value="Underline"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="T" Property="TextDecorations" Value="Underline"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Grid Background="Transparent">
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Border x:Name="Box" Width="18" Height="18" CornerRadius="4" BorderThickness="1" VerticalAlignment="Top" Margin="0,1,0,0"
                      BorderBrush="{StaticResource ControlStrong}" Background="{StaticResource Control}">
                <Path x:Name="Mark" Data="M3.5,8.5 L6.8,11.8 L12.8,5" Stroke="{StaticResource OnAccent}" StrokeThickness="1.8"
                      StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Top"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Fg2}"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Box" Property="Background" Value="{StaticResource Accent}"/>
                <Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter TargetName="Mark" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Fg}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="Row" Background="Transparent" CornerRadius="4" Padding="10,7" BorderThickness="1" BorderBrush="Transparent">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Grid Width="18" Height="18" VerticalAlignment="Top" Margin="0,1,0,0">
                  <Ellipse x:Name="Ring" Stroke="{StaticResource ControlStrong}" StrokeThickness="1" Fill="{StaticResource Control}"/>
                  <Ellipse x:Name="Dot" Width="8" Height="8" Fill="{StaticResource OnAccent}" Visibility="Collapsed"/>
                </Grid>
                <ContentPresenter Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Top"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Row" Property="Background" Value="{StaticResource Hover}"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Ring" Property="Fill" Value="{StaticResource Accent}"/>
                <Setter TargetName="Ring" Property="Stroke" Value="{StaticResource Accent}"/>
                <Setter TargetName="Dot" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Row" Property="BorderBrush" Value="{StaticResource Fg}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="CaretBrush" Value="{StaticResource Fg}"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="B" Background="{StaticResource Control}" BorderBrush="{StaticResource ControlLine}" BorderThickness="1,1,1,2" CornerRadius="4">
              <ScrollViewer x:Name="PART_ContentHost" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Thin scroll bars (vertical; horizontal scrolling is off everywhere) -->
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="12"/>
      <Setter Property="MinWidth" Value="12"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb"><Border Background="{StaticResource Fg3}" Opacity="0.55" CornerRadius="3" Margin="4,2"/></ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- On/off switch (a CheckBox) -->
    <Style x:Key="Switch" TargetType="CheckBox">
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <TextBlock x:Name="State" Text="Off" Width="28" Foreground="{StaticResource Fg2}" VerticalAlignment="Center" TextAlignment="Right" Margin="0,0,10,0"/>
              <Grid Width="40" Height="20">
                <Border x:Name="Track" CornerRadius="10" BorderThickness="1" BorderBrush="{StaticResource ControlStrong}" Background="{StaticResource Control}"/>
                <Ellipse x:Name="Knob" Width="12" Height="12" Fill="{StaticResource Fg2}" HorizontalAlignment="Left" Margin="4,0,0,0"/>
              </Grid>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Track" Property="BorderBrush" Value="{StaticResource Fg2}"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="{StaticResource Accent}"/>
                <Setter TargetName="Track" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter TargetName="Knob" Property="Fill" Value="{StaticResource OnAccent}"/>
                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Knob" Property="Margin" Value="0,0,4,0"/>
                <Setter TargetName="State" Property="Text" Value="On"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Track" Property="BorderBrush" Value="{StaticResource Fg}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Options side by side (RadioButtons) -->
    <Style x:Key="Seg" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="B" Background="{StaticResource Control}" BorderBrush="{StaticResource ControlLine}" BorderThickness="1" CornerRadius="4" Padding="12,5" Margin="6,0,0,0">
              <ContentPresenter HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="{StaticResource ControlStrong}"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="B" Property="Background" Value="{StaticResource Accent}"/>
                <Setter TargetName="B" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter Property="Foreground" Value="{StaticResource OnAccent}"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="{StaticResource Fg}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Tabs of a page (RadioButtons) -->
    <Style x:Key="Tab" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{StaticResource Fg2}"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <StackPanel Margin="0,0,24,0" Background="Transparent">
              <ContentPresenter Margin="0,0,0,6"/>
              <Border x:Name="Bar" Height="3" CornerRadius="1.5" Background="{StaticResource Accent}" Visibility="Hidden"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="{StaticResource Fg}"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bar" Property="Visibility" Value="Visible"/>
                <Setter Property="Foreground" Value="{StaticResource Fg}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="MaxDropDownHeight" Value="320"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton Focusable="False" ClickMode="Press" Cursor="Hand"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="B" Background="{StaticResource Control}" BorderBrush="{StaticResource ControlLine}" BorderThickness="1" CornerRadius="4">
                      <Path HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0" Data="M0,0 L4,4 L8,0" Stroke="{StaticResource Fg2}" StrokeThickness="1.4"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="{StaticResource ControlStrong}"/></Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter IsHitTestVisible="False" Margin="10,0,30,0" VerticalAlignment="Center"
                                Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/>
              <Popup IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
                <Border Background="{StaticResource Card}" BorderBrush="{StaticResource Line}" BorderThickness="1" CornerRadius="6" Padding="4" Margin="0,4,0,0"
                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" MaxHeight="{TemplateBinding MaxDropDownHeight}">
                  <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><ItemsPresenter/></ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="B" Padding="10,6" CornerRadius="4" Background="Transparent"><ContentPresenter/></Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="B" Property="Background" Value="{StaticResource Selected}"/></Trigger>
              <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="B" Property="Background" Value="{StaticResource Hover}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- One option of a page: Windows Settings style row -->
    <Style x:Key="RowBox" TargetType="Border">
      <Setter Property="Background" Value="{StaticResource Card}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="6"/>
      <Setter Property="Padding" Value="16,12"/>
      <Setter Property="Margin" Value="0,0,0,4"/>
    </Style>

    <Style x:Key="CardBox" TargetType="Border">
      <Setter Property="Background" Value="{StaticResource Card}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="8"/>
      <Setter Property="Padding" Value="20,18"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="260"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- Sidebar -->
    <DockPanel Grid.Column="0">
      <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="22,20,16,14">
        <Image x:Name="Logo" Width="30" Height="30"/>
        <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
          <TextBlock Text="TidyWin" FontSize="14" FontWeight="SemiBold"/>
          <TextBlock x:Name="OsLabel" FontSize="11.5" Foreground="{StaticResource Fg2}"/>
        </StackPanel>
      </StackPanel>
      <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
        <StackPanel x:Name="Nav" Margin="10,0,10,16"/>
      </ScrollViewer>
    </DockPanel>

    <!-- Page -->
    <Border Grid.Column="1" Background="{StaticResource PageBg}" BorderBrush="{StaticResource Line}" BorderThickness="1,1,0,0" CornerRadius="8,0,0,0">
      <Grid Margin="36,28,36,22">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock x:Name="PageTitle" FontFamily="Segoe UI Variable Display, Segoe UI" FontSize="16" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>

        <!-- Before running: what it does, and the button -->
        <ScrollViewer x:Name="Intro" Grid.Row="2" Margin="0,22,0,0" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
          <StackPanel MaxWidth="760" HorizontalAlignment="Left">
            <Border Style="{StaticResource CardBox}">
              <StackPanel>
                <TextBlock Text="What it does" FontWeight="SemiBold" Margin="0,0,0,10"/>
                <StackPanel x:Name="Points"/>
              </StackPanel>
            </Border>
            <StackPanel Orientation="Horizontal" Margin="0,20,0,0">
              <Button x:Name="StartBtn" Style="{StaticResource Primary}" MinWidth="120"/>
              <TextBlock x:Name="IntroNote" Margin="16,0,0,0" VerticalAlignment="Center" Foreground="{StaticResource Fg2}" TextWrapping="Wrap"/>
            </StackPanel>
          </StackPanel>
        </ScrollViewer>

        <!-- Options on a page (Windows...): read from the script, in tabs -->
        <TextBlock x:Name="Loading" Grid.Row="2" Margin="0,24,0,0" Foreground="{StaticResource Fg2}" TextWrapping="Wrap" Visibility="Collapsed"/>
        <!-- Reading the options: a turning ring in the middle -->
        <Grid x:Name="Spinner" Grid.Row="2" Width="40" Height="40" HorizontalAlignment="Center" VerticalAlignment="Center"
              RenderTransformOrigin="0.5,0.5" Visibility="Collapsed">
          <Grid.RenderTransform><RotateTransform/></Grid.RenderTransform>
          <Ellipse Stroke="{StaticResource Line}" StrokeThickness="3"/>
          <Path Stroke="{StaticResource Accent}" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round"
                Data="M20,1.5 A18.5,18.5 0 0 1 38.5,20"/>
          <Grid.Triggers>
            <EventTrigger RoutedEvent="FrameworkElement.Loaded">
              <BeginStoryboard>
                <Storyboard RepeatBehavior="Forever">
                  <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(RotateTransform.Angle)" From="0" To="360" Duration="0:0:0.9"/>
                </Storyboard>
              </BeginStoryboard>
            </EventTrigger>
          </Grid.Triggers>
        </Grid>
        <Grid x:Name="FormView" Grid.Row="2" Margin="0,18,0,0" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <WrapPanel x:Name="Tabs" Margin="0,0,0,14"/>
          <ScrollViewer x:Name="FormScroll" Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False"/>
        </Grid>
        <ScrollViewer x:Name="ReviewView" Grid.Row="2" Margin="0,22,0,0" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False" Visibility="Collapsed">
          <StackPanel x:Name="ReviewList" MaxWidth="820" HorizontalAlignment="Left"/>
        </ScrollViewer>

        <!-- Running: the question card (when there is one) above the log -->
        <Grid x:Name="Run" Grid.Row="2" Margin="0,20,0,0" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition x:Name="QuestionRow" Height="Auto"/>
            <RowDefinition x:Name="LogRow" Height="*"/>
          </Grid.RowDefinitions>
          <ContentControl x:Name="Question" Focusable="False"/>
          <Border Grid.Row="1" Background="{StaticResource LogBg}" BorderBrush="{StaticResource Line}" BorderThickness="1" CornerRadius="8" Margin="0,12,0,0">
            <RichTextBox x:Name="Log" IsReadOnly="True" IsDocumentEnabled="True" BorderThickness="0" Background="Transparent"
                         Foreground="{StaticResource Fg}" FontFamily="Cascadia Mono, Consolas" FontSize="12" Padding="8,10"
                         VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"/>
          </Border>
        </Grid>

        <Grid x:Name="Footer" Grid.Row="3" Margin="0,14,0,0" Visibility="Collapsed">
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <ContentControl x:Name="FooterSlot" VerticalAlignment="Center" Margin="0,0,20,0" Visibility="Collapsed"/>
            <TextBlock x:Name="Status" VerticalAlignment="Center" Foreground="{StaticResource Fg2}"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="CopyBtn" Content="Copy log" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
            <Button x:Name="StopBtn" Content="Stop" Style="{StaticResource Btn}"/>
            <Button x:Name="DoneBtn" Content="Done" Style="{StaticResource Primary}" Visibility="Collapsed"/>
            <Button x:Name="RetryBtn" Content="Try again" Style="{StaticResource Btn}" Visibility="Collapsed"/>
            <Button x:Name="BackBtn" Content="Back" Style="{StaticResource Btn}" Margin="0,0,8,0" Visibility="Collapsed"/>
            <Button x:Name="ReviewBtn" Content="Review" Style="{StaticResource Primary}" Visibility="Collapsed"/>
            <Button x:Name="ApplyBtn" Content="Apply" Style="{StaticResource Primary}" Visibility="Collapsed"/>
          </StackPanel>
        </Grid>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

#endregion


#region ==================== 3. RUNNING A SCRIPT ====================

# The script runs in its own powershell.exe; its output is read on other threads into a queue that the
# window empties on a timer (PowerShell code can't run on those threads).
if (-not ('TidyWinPanel.Runner' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace TidyWinPanel {
    public class Runner {
        private Process proc;
        private int open;
        public readonly ConcurrentQueue<string> Lines = new ConcurrentQueue<string>();

        public bool Done { get { return proc != null && Volatile.Read(ref open) == 0 && proc.HasExited; } }
        public int ExitCode { get { try { return proc.ExitCode; } catch { return -1; } } }

        public void Start(string arguments) {
            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe", arguments);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = false;           // shares the panel's hidden console
            psi.RedirectStandardInput = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = new UTF8Encoding(false);
            psi.StandardErrorEncoding = new UTF8Encoding(false);
            psi.EnvironmentVariables["TIDYWIN_PANEL"] = "1";
            proc = new Process();
            proc.StartInfo = psi;
            open = 2;
            proc.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) {
                if (e.Data == null) Interlocked.Decrement(ref open); else Lines.Enqueue(e.Data);
            };
            proc.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) {
                if (e.Data == null) Interlocked.Decrement(ref open); else Lines.Enqueue("\u0001Red\u0002" + e.Data);
            };
            proc.Start();
            proc.BeginOutputReadLine();
            proc.BeginErrorReadLine();
        }

        public void Send(string line) {
            try {
                byte[] bytes = new UTF8Encoding(false).GetBytes(line + "\n");
                proc.StandardInput.BaseStream.Write(bytes, 0, bytes.Length);
                proc.StandardInput.BaseStream.Flush();
            } catch { }
        }

        // Ends the script and everything it started (installers, DISM...)
        public void Stop() {
            if (proc == null || proc.HasExited) return;
            try {
                ProcessStartInfo k = new ProcessStartInfo("taskkill.exe", "/T /F /PID " + proc.Id);
                k.UseShellExecute = false;
                k.CreateNoWindow = true;
                Process.Start(k).WaitForExit(10000);
            } catch { }
            try { if (!proc.HasExited) proc.Kill(); } catch { }
        }
    }

    public static class Native {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern int SetCurrentProcessExplicitAppUserModelID(string id);
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

        // Dark title bar (attribute 20; 19 on Windows 10 before 20H1)
        public static void DarkTitleBar(IntPtr hwnd) {
            int on = 1;
            if (DwmSetWindowAttribute(hwnd, 20, ref on, 4) != 0) DwmSetWindowAttribute(hwnd, 19, ref on, 4);
        }
    }
}
'@
}

$S = @{
    Item = $null; Steps = @(); StepIndex = -1; Runner = $null; Active = $false; Running = $false; Stopped = $false; Failed = $false
    Watch = $null; Question = $null; Rows = $null; Groups = $null; WaitPath = $null; KeepUntil = $null; Ticks = 0
}

# The command line of a step: UTF-8 in and out, download the script (unless there is a local copy) and run it.
# $Extra: more arguments, already quoted (-Describe / -Answers and a file).
function Get-StepCommand($Step, [string]$Extra) {
    $local = Join-Path $PSScriptRoot $Step.Script
    $file  = if (Test-Path -LiteralPath $local) { $local } else { Join-Path $PSScriptRoot (Split-Path $Step.Script -Leaf) }
    $q = { param($value) "'" + ($value -replace "'", "''") + "'" }
    $lines = @(
        '[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false'
        '[Console]::InputEncoding = New-Object Text.UTF8Encoding $false'
        '$ProgressPreference = ''SilentlyContinue'''
        '[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12'
    )
    if ($file -ne $local) {
        $url = "$Base/scripts/$($Step.Script)"
        $lines += "try { Invoke-WebRequest -Uri $(& $q $url) -OutFile $(& $q $file) -UseBasicParsing -ErrorAction Stop }"
        $lines += "catch { Write-Host ""Could not download the script: `$(`$_.Exception.Message)""; exit 2 }"
    }
    $lines += "& $(& $q $file) $(($Step.Args | ForEach-Object { $_ }) -join ' ') $Extra"
    # A small script file, run with -File: with -EncodedCommand and the output redirected, PowerShell
    # writes warnings, errors and progress as XML. The file deletes itself once it is running.
    $runner = Join-Path $env:TEMP "tidywin-run-$([guid]::NewGuid().ToString('N').Substring(0, 8)).ps1"
    $lines = @('Remove-Item -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue') + $lines
    [IO.File]::WriteAllText($runner, ($lines -join "`r`n"), (New-Object Text.UTF8Encoding $true))
    return "-NoProfile -ExecutionPolicy Bypass -File `"$runner`""
}

function Start-Item($Item, [string]$Extra) {
    $S.Item = $Item; $S.Steps = @($Item.Steps); $S.StepIndex = -1; $S.Extra = $Extra
    $S.Active = $true; $S.Stopped = $false; $S.Failed = $false
    $S.Watch = [Diagnostics.Stopwatch]::StartNew()
    $ui.Log.Document = New-LogDocument
    Show-Page $Item
    Set-NavBusy $Item.Id $true
    Start-NextStep
}

# Next step of the option; options with several steps ask before each one.
function Start-NextStep {
    $S.StepIndex++
    if ($S.Stopped -or $S.StepIndex -ge $S.Steps.Count) { Complete-Item; return }
    $step = $S.Steps[$S.StepIndex]
    if ($S.Steps.Count -gt 1) { Show-StepCard $step } else { Start-Script $step }
}

function Start-Script($Step) {
    if ($Step.Name) { Add-LogLine ([string][char]1 + 'Cyan' + [char]2 + "▸ Step $($S.StepIndex + 1) of $($S.Steps.Count): $($Step.Name)") }
    $S.Runner = New-Object TidyWinPanel.Runner
    try {
        $S.Runner.Start((Get-StepCommand $Step $S.Extra))
        $S.Running = $true
    } catch {
        Add-LogLine ([string][char]1 + 'Red' + [char]2 + "Could not start the script: $($_.Exception.Message)")
        $S.Failed = $true
        Complete-Item
    }
    Update-Footer
}

function Stop-Run {
    if (-not $S.Running) { return }
    $S.Stopped = $true
    Clear-Question
    $S.Runner.Stop()
}

# When the script ends: the next step, or the end.
function Complete-Script {
    $S.Running = $false
    Clear-Question
    $code = $S.Runner.ExitCode
    if ($S.Stopped) { Add-LogLine ([string][char]1 + 'Yellow' + [char]2 + 'Stopped.') }
    elseif ($code -ne 0) { $S.Failed = $true; Add-LogLine ([string][char]1 + 'Red' + [char]2 + "The script ended with an error (code $code).") }
    Start-NextStep
}

function Complete-Item {
    $S.Running = $false
    $S.Active = $false
    Clear-Question
    if ($S.Watch) { $S.Watch.Stop() }
    if ($S.Item) { Set-NavBusy $S.Item.Id $false }
    if ($S.AnswersFile) { Remove-Item -LiteralPath $S.AnswersFile -ErrorAction SilentlyContinue; $S.AnswersFile = $null }
    Update-Footer
    # The PC changed: every page is read again, and the one open now (if it isn't this log) right away
    Reset-Pages
    if ($script:Page -and $script:Page.Id -ne $S.Item.Id) { Show-Page $script:Page }
}

# Runs on the window's timer: shows new output, handles questions and notices the end.
function Update-Run {
    $S.Ticks++
    if ($Describes.Count) { Update-Describes }
    if ($S.Running) {
        $follow = Test-LogAtEnd
        $line = $null; $count = 0
        while ($count -lt 400 -and $S.Runner.Lines.TryDequeue([ref]$line)) {
            $count++
            if ($line.StartsWith('##TIDYWIN ')) {
                try { Show-Question (ConvertFrom-Json $line.Substring(10)) }
                catch { Add-LogLine ([string][char]1 + 'Red' + [char]2 + "Could not show a question: $($_.Exception.Message)") }
            } else { Add-LogLine $line }
        }
        if ($count -and $follow) { $ui.Log.ScrollToEnd() }
        if ($count -eq 0 -and $S.Runner.Done) { Complete-Script }
    }
    # Waiting for something to disappear (an uninstalled program): goes on by itself
    if ($S.WaitPath -and ($S.Ticks % 10) -eq 0 -and -not (Test-Path -LiteralPath $S.WaitPath)) { Send-Answer $true 'done' }
    if ($S.KeepUntil) {
        $left = [Math]::Ceiling(($S.KeepUntil - (Get-Date)).TotalSeconds)
        if ($left -le 0) { Send-Answer $false 'went back' }
        elseif ($S.KeepText) { $S.KeepText.Text = "Goes back by itself in $left s." }
    }
    if (($S.Ticks % 15) -eq 0) { Update-Footer }
}

function Format-Elapsed { $e = $S.Watch.Elapsed; '{0}:{1:D2}' -f [int][Math]::Floor($e.TotalMinutes), $e.Seconds }

function Update-Footer {
    if (-not $S.Item -or $ui.Run.Visibility -ne 'Visible') { return }
    $ui.Footer.Visibility = 'Visible'
    if ($S.Active) {
        $ui.Status.Text = if ($ui.Question.Content) { "Waiting for you · $(Format-Elapsed)" } else { "Running · $(Format-Elapsed)" }
        $ui.Status.Foreground = $W.Resources['Fg2']
        $ui.StopBtn.Visibility = 'Visible'; $ui.DoneBtn.Visibility = 'Collapsed'
    } else {
        if ($S.Stopped)    { $ui.Status.Text = "Stopped · $(Format-Elapsed)";                $ui.Status.Foreground = $W.Resources['Warn'] }
        elseif ($S.Failed) { $ui.Status.Text = "Finished with an error · $(Format-Elapsed)"; $ui.Status.Foreground = $W.Resources['Err'] }
        else               { $ui.Status.Text = "Finished · $(Format-Elapsed)";               $ui.Status.Foreground = $W.Resources['Ok'] }
        $ui.StopBtn.Visibility = 'Collapsed'; $ui.DoneBtn.Visibility = 'Visible'
    }
}

#endregion


#region ==================== 4. LOG ====================

function New-LogDocument {
    $doc = New-Object Windows.Documents.FlowDocument
    $doc.PagePadding = New-Object Windows.Thickness 0
    $doc.FontFamily = $ui.Log.FontFamily
    $doc.FontSize = $ui.Log.FontSize
    $doc.Foreground = $W.Resources['Fg']
    return $doc
}

function Test-LogAtEnd { ($ui.Log.VerticalOffset + $ui.Log.ViewportHeight) -ge ($ui.Log.ExtentHeight - 24) }

# Console colors used by the scripts, as the panel shows them.
function Get-LogStyle([string]$Color) {
    switch ($Color) {
        { $_ -in 'Green', 'DarkGreen' }     { return @($W.Resources['Ok'], 'Normal') }
        { $_ -in 'Red', 'DarkRed' }         { return @($W.Resources['Err'], 'Normal') }
        { $_ -in 'Yellow', 'DarkYellow' }   { return @($W.Resources['Warn'], 'Normal') }
        { $_ -in 'Cyan', 'DarkCyan', 'Blue', 'Magenta' } { return @($W.Resources['Accent'], 'SemiBold') }
        'DarkGray'                          { return @($W.Resources['Fg3'], 'Normal') }
        'Answer'                            { return @($W.Resources['Accent'], 'Normal') }
        default                             { return @($W.Resources['Fg'], 'Normal') }
    }
}

# Adds text to a paragraph; web addresses become links.
function Add-LogText($Paragraph, [string]$Text, [string]$Color) {
    $style = Get-LogStyle $Color
    $pos = 0
    foreach ($m in [regex]::Matches($Text, 'https?://[^\s"''<>)\]]+')) {
        if ($m.Index -gt $pos) { $r = New-Object Windows.Documents.Run ($Text.Substring($pos, $m.Index - $pos)); $r.Foreground = $style[0]; $r.FontWeight = [Windows.FontWeights]::($style[1]); $Paragraph.Inlines.Add($r) }
        $link = New-Object Windows.Documents.Hyperlink (New-Object Windows.Documents.Run $m.Value)
        $link.Foreground = $W.Resources['Accent']
        $link.Tag = $m.Value
        $link.Add_Click({ Start-Process $this.Tag })
        $Paragraph.Inlines.Add($link)
        $pos = $m.Index + $m.Length
    }
    if ($pos -lt $Text.Length) { $r = New-Object Windows.Documents.Run ($Text.Substring($pos)); $r.Foreground = $style[0]; $r.FontWeight = [Windows.FontWeights]::($style[1]); $Paragraph.Inlines.Add($r) }
}

# One line of output. Lines from Write-Host carry their color: [char]1 + color + [char]2 + text (one or more).
function Add-LogLine([string]$Raw) {
    $text = $Raw.Replace([string][char]0, '')                      # sfc writes UTF-16
    $cr = $text.LastIndexOf("`r"); if ($cr -ge 0) { $text = $text.Substring($cr + 1) }   # progress redrawn on one line
    $p = New-Object Windows.Documents.Paragraph
    $p.Margin = New-Object Windows.Thickness 0
    if ($text.Contains([string][char]1)) {
        foreach ($part in ($text -split [char]1)) {
            if (-not $part) { continue }
            $sep = $part.IndexOf([char]2)
            if ($sep -lt 0) { Add-LogText $p $part ''; continue }
            Add-LogText $p $part.Substring($sep + 1) $part.Substring(0, $sep)
        }
    } else {
        # Output of other programs: skip spinners and progress bars (winget), color warnings
        if ($text -match '^\s*[-\\|/]\s*$' -or $text -match '[█▒]') { return }
        $color = if ($text -match '^(WARNING|AVISO|ADVERTÊNCIA):') { 'Yellow' } else { '' }
        Add-LogText $p $text $color
    }
    $blocks = $ui.Log.Document.Blocks
    $blocks.Add($p)
    while ($blocks.Count -gt 5000) { [void]$blocks.Remove($blocks.FirstBlock) }
}

#endregion


#region ==================== 5. QUESTION CARDS ====================

function New-Text([string]$Text, [double]$Size = 13, [string]$Weight = 'Normal', [string]$Brush = 'Fg') {
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Text; $t.FontSize = $Size; $t.FontWeight = [Windows.FontWeights]::$Weight; $t.TextWrapping = 'Wrap'
    $t.Foreground = $W.Resources[$Brush]
    return $t
}

function New-Button([string]$Text, [switch]$Primary) {
    $b = New-Object Windows.Controls.Button
    $b.Content = $Text
    $b.Style = $W.Resources[$(if ($Primary) { 'Primary' } else { 'Btn' })]
    $b.Margin = New-Object Windows.Thickness 8, 0, 0, 0
    return $b
}

function New-Card {
    $c = New-Object Windows.Controls.Border
    $c.Style = $W.Resources['CardBox']
    return $c
}

function New-ButtonRow {
    $row = New-Object Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'
    $row.Margin = New-Object Windows.Thickness 0, 16, 0, 0
    return $row
}

# Shows a card above the log. A checklist takes most of the height; the log shrinks below it.
function Set-QuestionCard($Card, [switch]$Tall) {
    $ui.Question.Content = $Card
    if ($Tall) {
        $ui.QuestionRow.Height = New-Object Windows.GridLength 1, 'Star'
        $ui.LogRow.Height = New-Object Windows.GridLength 140
    } else {
        $ui.QuestionRow.Height = [Windows.GridLength]::Auto
        $ui.LogRow.Height = New-Object Windows.GridLength 1, 'Star'
    }
    Update-Footer
}

function Clear-Question {
    $S.Question = $null; $S.WaitPath = $null; $S.KeepUntil = $null; $S.KeepText = $null; $S.Rows = $null
    $ui.Question.Content = $null
    $ui.QuestionRow.Height = [Windows.GridLength]::Auto
    $ui.LogRow.Height = New-Object Windows.GridLength 1, 'Star'
}

# The answer goes back to the script as {"value": ...}, and a line in the log records it.
function Send-Answer($Value, [string]$Shown) {
    if (-not $S.Question) { return }
    $question = "$($S.Question.question)".Trim()
    if (-not $question) { $question = "$($S.Question.title)".Trim() }
    $S.Runner.Send((ConvertTo-Json @{ value = $Value } -Compress -Depth 6))
    Add-LogLine ([string][char]1 + 'Answer' + [char]2 + "› $question  $Shown")
    $ui.Log.ScrollToEnd()
    Clear-Question
    Update-Footer
}

# Focus a control once the card is on screen (Enter then answers).
function Set-FocusLater($Control) {
    [void]$W.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Input, [Action]{ [void]$Control.Focus() }.GetNewClosure())
}

function Show-Question($Q) {
    $S.Question = $Q
    switch ($Q.type) {
        'choose'    { Show-ChooseCard $Q }
        'checklist' { Show-ChecklistCard $Q }
        'wait'      { Show-WaitCard $Q }
        'keep'      { Show-KeepCard $Q }
        default     { Show-TextCard $Q }      # text, folder, file
    }
}

# A choice: Yes / No as two buttons, anything else as a list.
function Show-ChooseCard($Q) {
    $options = @($Q.options)
    $default = [int]$Q.default
    if ($default -lt 0 -or $default -ge $options.Count) { $default = 0 }
    $card = New-Card
    $stack = New-Object Windows.Controls.StackPanel
    $stack.Children.Add((New-Text $Q.question 16 'SemiBold')) | Out-Null
    $buttons = New-ButtonRow

    if ($options.Count -eq 2 -and $options[0] -eq 'Yes' -and $options[1] -eq 'No') {
        $buttons.HorizontalAlignment = 'Left'
        $buttons.Margin = New-Object Windows.Thickness -8, 16, 0, 0
        for ($i = 0; $i -lt 2; $i++) {
            $b = New-Button $options[$i] -Primary:($i -eq $default)
            $b.Tag = $i
            $b.IsDefault = $i -eq $default
            $b.Add_Click({ Send-Answer ([int]$this.Tag) $S.Question.options[[int]$this.Tag] })
            $buttons.Children.Add($b) | Out-Null
            if ($i -eq $default) { Set-FocusLater $b }
        }
        $stack.Children.Add($buttons) | Out-Null
    } else {
        $list = New-Object Windows.Controls.StackPanel
        $list.Margin = New-Object Windows.Thickness -10, 10, 0, 0
        for ($i = 0; $i -lt $options.Count; $i++) {
            $r = New-Object Windows.Controls.RadioButton
            $r.Content = New-Text $options[$i]
            $r.GroupName = 'question'
            $r.Tag = $i
            $r.IsChecked = $i -eq $default
            $r.Add_MouseDoubleClick({ Send-Answer ([int]$this.Tag) $S.Question.options[[int]$this.Tag] })
            $list.Children.Add($r) | Out-Null
            if ($i -eq $default) { Set-FocusLater $r }
        }
        $scroll = New-Object Windows.Controls.ScrollViewer
        $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.HorizontalScrollBarVisibility = 'Disabled'
        $scroll.MaxHeight = 330
        $scroll.Content = $list
        $stack.Children.Add($scroll) | Out-Null
        $ok = New-Button 'Continue' -Primary
        $ok.IsDefault = $true
        $ok.Tag = $list
        $ok.Add_Click({
            $picked = @($this.Tag.Children | Where-Object { $_.IsChecked })[0]
            Send-Answer ([int]$picked.Tag) $S.Question.options[[int]$picked.Tag]
        })
        $buttons.Children.Add($ok) | Out-Null
        $stack.Children.Add($buttons) | Out-Null
    }
    $card.Child = $stack
    Set-QuestionCard $card
}

# A list to check, with groups, an optional search and an optional second box per item (flagLabel).
function Show-ChecklistCard($Q) {
    $items = @($Q.items)
    $S.Rows = New-Object System.Collections.Generic.List[object]
    $S.Groups = @{}
    $card = New-Card
    $grid = New-Object Windows.Controls.Grid
    foreach ($h in 'Auto', 'Star', 'Auto') {
        $rd = New-Object Windows.Controls.RowDefinition
        $rd.Height = if ($h -eq 'Auto') { [Windows.GridLength]::Auto } else { New-Object Windows.GridLength 1, 'Star' }
        $grid.RowDefinitions.Add($rd)
    }

    # Title and search
    $head = New-Object Windows.Controls.DockPanel
    $head.Margin = New-Object Windows.Thickness 0, 0, 0, 10
    if ($Q.search -or $items.Count -gt 15) {
        $box = New-Object Windows.Controls.Grid
        $box.Width = 240
        [Windows.Controls.DockPanel]::SetDock($box, 'Right')
        $search = New-Object Windows.Controls.TextBox
        $hint = New-Text 'Search' 13 'Normal' 'Fg3'
        $hint.Margin = New-Object Windows.Thickness 11, 0, 0, 0       # border + padding + the text box's own 2
        $hint.VerticalAlignment = 'Center'; $hint.IsHitTestVisible = $false
        $search.VerticalAlignment = 'Center'
        $box.VerticalAlignment = 'Center'
        $search.Tag = $hint
        $search.Add_TextChanged({
            $this.Tag.Visibility = if ($this.Text) { 'Collapsed' } else { 'Visible' }
            Update-ChecklistFilter $this.Text
        })
        $box.Children.Add($search) | Out-Null
        $box.Children.Add($hint) | Out-Null
        $head.Children.Add($box) | Out-Null
    }
    if ("$($Q.title)") {
        $title = New-Text $Q.title 16 'SemiBold'
        $title.VerticalAlignment = 'Center'
        $head.Children.Add($title) | Out-Null
    }
    if (-not $head.Children.Count) { $head.Visibility = 'Collapsed' }    # a list with no title and no search
    $grid.Children.Add($head) | Out-Null

    # Items
    $list = New-Object Windows.Controls.StackPanel
    $last = $null
    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]
        $group = "$($it.group)"
        if ($group -and $group -ne $last) {
            $gh = New-Object Windows.Controls.DockPanel
            $gh.Margin = New-Object Windows.Thickness 0, $(if ($last) { 14 } else { 2 }), 0, 4
            $link = New-Object Windows.Controls.Button
            $link.Style = $W.Resources['Link']; $link.Content = 'Select all'; $link.Tag = $group
            $link.Margin = New-Object Windows.Thickness 0, 0, 12, 0
            [Windows.Controls.DockPanel]::SetDock($link, 'Right')
            $link.Add_Click({
                $rows = $S.Groups[$this.Tag].Rows.ToArray()       # @(List) fails in 5.1: "argument types do not match"
                $all = @($rows | Where-Object { -not $_.Check.IsChecked }).Count -eq 0
                foreach ($r in $rows) { $r.Check.IsChecked = -not $all }
            })
            $gh.Children.Add($link) | Out-Null
            $gh.Children.Add((New-Text $group 12 'SemiBold' 'Fg2')) | Out-Null
            $list.Children.Add($gh) | Out-Null
            $S.Groups[$group] = @{ Header = $gh; Link = $link; Rows = New-Object System.Collections.Generic.List[object] }
            $last = $group
        }

        $rowGrid = New-Object Windows.Controls.Grid
        $rowGrid.Margin = New-Object Windows.Thickness 0, 5, 0, 5
        foreach ($size in 'Star', 'Auto') {
            $cd = New-Object Windows.Controls.ColumnDefinition
            $cd.Width = if ($size -eq 'Auto') { [Windows.GridLength]::Auto } else { New-Object Windows.GridLength 1, 'Star' }
            $rowGrid.ColumnDefinitions.Add($cd)
        }
        $content = New-Object Windows.Controls.StackPanel
        $content.Children.Add((New-Text "$($it.label)")) | Out-Null
        if ("$($it.note)") { $content.Children.Add((New-Text "$($it.note)" 12 'Normal' 'Fg2')) | Out-Null }
        $check = New-Object Windows.Controls.CheckBox
        $check.Content = $content
        $check.IsChecked = [bool]$it.checked
        $check.Add_Checked({ Update-ChecklistCount })
        $check.Add_Unchecked({ Update-ChecklistCount })
        $rowGrid.Children.Add($check) | Out-Null

        $flag = $null
        if ($Q.flagLabel -and $null -ne $it.flag) {
            $flag = New-Object Windows.Controls.CheckBox
            $flag.Content = New-Text $Q.flagLabel 12.5 'Normal' 'Fg2'
            $flag.ToolTip = $Q.flagHint
            $flag.IsChecked = [bool]$it.flag
            $flag.Margin = New-Object Windows.Thickness 16, 0, 12, 0
            $flag.Tag = $check
            $flag.Add_Checked({ $this.Tag.IsChecked = $true })     # opening the installer also selects the app
            [Windows.Controls.Grid]::SetColumn($flag, 1)
            $rowGrid.Children.Add($flag) | Out-Null
        }
        $list.Children.Add($rowGrid) | Out-Null
        $row = @{ Index = $i; Check = $check; Flag = $flag; Row = $rowGrid; Group = $group; Text = "$($it.label) $($it.note)" }
        $S.Rows.Add($row)
        if ($group) { $S.Groups[$group].Rows.Add($row) }
    }
    $scroll = New-Object Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.HorizontalScrollBarVisibility = 'Disabled'
    $scroll.Content = $list
    [Windows.Controls.Grid]::SetRow($scroll, 1)
    $grid.Children.Add($scroll) | Out-Null

    # Count and buttons
    $foot = New-Object Windows.Controls.DockPanel
    $foot.Margin = New-Object Windows.Thickness 0, 14, 0, 0
    $buttons = New-Object Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    [Windows.Controls.DockPanel]::SetDock($buttons, 'Right')
    if ($Q.cancel -ne $false) {
        $cancel = New-Button 'Cancel'
        $cancel.Add_Click({ Send-Answer $null 'cancelled' })
        $buttons.Children.Add($cancel) | Out-Null
    }
    $ok = New-Button 'Continue' -Primary
    $ok.Add_Click({
        $checked = @($S.Rows | Where-Object { $_.Check.IsChecked } | ForEach-Object { $_.Index })
        $flags   = @($S.Rows | Where-Object { $_.Flag -and $_.Flag.IsChecked } | ForEach-Object { $_.Index })
        Send-Answer @{ checked = $checked; flags = $flags } "$($checked.Count) selected"
    })
    $buttons.Children.Add($ok) | Out-Null
    $foot.Children.Add($buttons) | Out-Null
    $S.CountText = New-Text '' 12 'Normal' 'Fg2'
    $S.CountText.VerticalAlignment = 'Center'
    $foot.Children.Add($S.CountText) | Out-Null
    [Windows.Controls.Grid]::SetRow($foot, 2)
    $grid.Children.Add($foot) | Out-Null

    $card.Child = $grid
    Set-QuestionCard $card -Tall
    Update-ChecklistCount
}

function Update-ChecklistCount {
    if (-not $S.Rows) { return }
    $n = @($S.Rows | Where-Object { $_.Check.IsChecked }).Count
    $S.CountText.Text = "$n selected"
    foreach ($g in $S.Groups.Values) {
        $all = @($g.Rows | Where-Object { -not $_.Check.IsChecked }).Count -eq 0
        $g.Link.Content = if ($all) { 'Clear' } else { 'Select all' }
    }
}

function Update-ChecklistFilter([string]$Text) {
    foreach ($r in $S.Rows) {
        $r.Row.Visibility = if (-not $Text -or $r.Text.IndexOf($Text, [StringComparison]::OrdinalIgnoreCase) -ge 0) { 'Visible' } else { 'Collapsed' }
    }
    foreach ($g in $S.Groups.Values) {
        $g.Header.Visibility = if (@($g.Rows | Where-Object { $_.Row.Visibility -eq 'Visible' }).Count) { 'Visible' } else { 'Collapsed' }
    }
}

# Typed answer; folders and files also have a Browse button.
function Show-TextCard($Q) {
    $card = New-Card
    $stack = New-Object Windows.Controls.StackPanel
    $question = switch ($Q.type) { 'folder' { 'Choose a folder' } 'file' { 'Choose the .json file' } default { "$($Q.question)".TrimEnd(':') } }
    if (-not $question) { $question = 'Type your answer' }
    $stack.Children.Add((New-Text $question 14 'SemiBold')) | Out-Null
    $row = New-Object Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.Margin = New-Object Windows.Thickness 0, 12, 0, 0
    $box = New-Object Windows.Controls.TextBox
    $box.Width = 460
    $box.Text = "$($Q.default)"
    $row.Children.Add($box) | Out-Null
    if ($Q.type -in 'folder', 'file') {
        $browse = New-Button 'Browse'
        $browse.Tag = $box
        $browse.Add_Click({
            if ($S.Question.type -eq 'folder') {
                $d = New-Object System.Windows.Forms.FolderBrowserDialog
                if ($this.Tag.Text -and (Test-Path -LiteralPath $this.Tag.Text)) { $d.SelectedPath = $this.Tag.Text }
                if ($d.ShowDialog() -eq 'OK') { $this.Tag.Text = $d.SelectedPath }
            } else {
                $d = New-Object Microsoft.Win32.OpenFileDialog
                $d.Filter = 'App list (*.json)|*.json|All files (*.*)|*.*'
                if ($d.ShowDialog($W)) { $this.Tag.Text = $d.FileName }
            }
        })
        $row.Children.Add($browse) | Out-Null
    }
    $stack.Children.Add($row) | Out-Null
    $buttons = New-ButtonRow
    $buttons.HorizontalAlignment = 'Left'
    $buttons.Margin = New-Object Windows.Thickness -8, 16, 0, 0
    $ok = New-Button 'Continue' -Primary
    $ok.IsDefault = $true
    $ok.Tag = $box
    $ok.Add_Click({ Send-Answer $this.Tag.Text $this.Tag.Text })
    $buttons.Children.Add($ok) | Out-Null
    $stack.Children.Add($buttons) | Out-Null
    $card.Child = $stack
    Set-QuestionCard $card
    Set-FocusLater $box
}

# The script waits for you to do something outside TidyWin (finish an installer, paste a key...).
function Show-WaitCard($Q) {
    $card = New-Card
    $stack = New-Object Windows.Controls.StackPanel
    $text = ("$($Q.question)" -replace '(?i)[,;]?\s*(then\s+)?press Enter( to | when )?', ' ').Trim(' ', ',', '.')
    if (-not $text) { $text = 'Continue when you are ready' }
    $stack.Children.Add((New-Text ($text.Substring(0, 1).ToUpper() + $text.Substring(1)) 16 'SemiBold')) | Out-Null
    if ($Q.untilGone) {
        $note = New-Text 'TidyWin goes on by itself when it is done.' 13 'Normal' 'Fg2'
        $note.Margin = New-Object Windows.Thickness 0, 4, 0, 0
        $stack.Children.Add($note) | Out-Null
        $S.WaitPath = "$($Q.untilGone)"
    }
    $buttons = New-ButtonRow
    $buttons.HorizontalAlignment = 'Left'
    $buttons.Margin = New-Object Windows.Thickness -8, 16, 0, 0
    $ok = New-Button $(if ($Q.button) { "$($Q.button)" } else { 'Continue' }) -Primary
    $ok.Add_Click({ Send-Answer $true 'continued' })
    $buttons.Children.Add($ok) | Out-Null
    $stack.Children.Add($buttons) | Out-Null
    $card.Child = $stack
    Set-QuestionCard $card
}

# Keep a change that may leave the screen unusable (resolution): goes back by itself if nobody answers.
function Show-KeepCard($Q) {
    $card = New-Card
    $stack = New-Object Windows.Controls.StackPanel
    $stack.Children.Add((New-Text $Q.question 16 'SemiBold')) | Out-Null
    $S.KeepText = New-Text '' 13 'Normal' 'Fg2'
    $S.KeepText.Margin = New-Object Windows.Thickness 0, 4, 0, 0
    $stack.Children.Add($S.KeepText) | Out-Null
    $S.KeepUntil = (Get-Date).AddSeconds([int]$Q.seconds)
    $buttons = New-ButtonRow
    $buttons.HorizontalAlignment = 'Left'
    $buttons.Margin = New-Object Windows.Thickness -8, 16, 0, 0
    $keep = New-Button 'Keep' -Primary
    $keep.IsDefault = $true
    $keep.Add_Click({ Send-Answer $true 'kept' })
    $back = New-Button 'Go back'
    $back.Add_Click({ Send-Answer $false 'went back' })
    $buttons.Children.Add($keep) | Out-Null
    $buttons.Children.Add($back) | Out-Null
    $stack.Children.Add($buttons) | Out-Null
    $card.Child = $stack
    Set-QuestionCard $card
    Set-FocusLater $keep
}

# Options with several steps (Back up, Restore): each one can be skipped.
function Show-StepCard($Step) {
    $S.Question = $null
    $card = New-Card
    $stack = New-Object Windows.Controls.StackPanel
    $stack.Children.Add((New-Text "Step $($S.StepIndex + 1) of $($S.Steps.Count): $($Step.Name)" 14 'SemiBold')) | Out-Null
    $buttons = New-ButtonRow
    $buttons.HorizontalAlignment = 'Left'
    $buttons.Margin = New-Object Windows.Thickness -8, 16, 0, 0
    $run = New-Button 'Start' -Primary
    $run.IsDefault = $true
    $run.Tag = $Step
    $run.Add_Click({ $step = $this.Tag; Clear-Question; Start-Script $step })
    $skip = New-Button 'Skip'
    $skip.Tag = $Step
    $skip.Add_Click({
        Add-LogLine ([string][char]1 + 'DarkGray' + [char]2 + "Skipped: $($this.Tag.Name)")
        Clear-Question
        Start-NextStep
    })
    $buttons.Children.Add($run) | Out-Null
    $buttons.Children.Add($skip) | Out-Null
    $stack.Children.Add($buttons) | Out-Null
    $card.Child = $stack
    Set-QuestionCard $card
    Set-FocusLater $run
}

#endregion


#region ==================== 6. OPTION PAGES ====================

# Options with -Form: the script describes its options (-Describe), the page shows all of them in tabs,
# Review lists what will change and Apply runs the script with the answers (-Answers). Nothing is asked.
# Nothing comes selected: switches off, no option picked. What is left alone is not changed.

$Forms = @{}          # option id -> its page, kept while TidyWin is open (rebuilt after applying)
$Describes = @{}      # option id -> the script reading the options of this PC

# An option with more than one script (Back up: apps, then drivers) describes each one in turn; the page
# has the tabs and fields of all of them, a field id that comes again (where to save) only once.
function Start-Describe($Item) {
    $d = @{ Item = $Item; Step = -1; Pages = New-Object System.Collections.Generic.List[object]; Output = New-Object System.Collections.Generic.List[string]; Failed = $false }
    $Describes[$Item.Id] = $d
    Start-DescribeStep $d
}

function Start-DescribeStep($D) {
    $D.Step++
    $D.File = Join-Path $env:TEMP "tidywin-$($D.Item.Id)-options-$($D.Step).json"
    Remove-Item -LiteralPath $D.File -ErrorAction SilentlyContinue
    $D.Runner = New-Object TidyWinPanel.Runner
    try { $D.Runner.Start((Get-StepCommand $D.Item.Steps[$D.Step] "-Describe '$($D.File -replace "'", "''")'")) }
    catch { $D.Output.Add($_.Exception.Message); $D.Failed = $true }
}

function Join-Pages([object[]]$Pages) {
    $ids = @{}
    $fields = foreach ($p in $Pages) { foreach ($f in @($p.fields)) { if (-not $ids.ContainsKey("$($f.id)")) { $ids["$($f.id)"] = 1; $f } } }
    [pscustomobject]@{
        tabs   = @($Pages | ForEach-Object { @($_.tabs) } | Where-Object { $_ } | Select-Object -Unique)
        notes  = @($Pages | ForEach-Object { @($_.notes) } | Where-Object { $_ })
        fields = @($fields)
    }
}

# On the timer: when a script has finished describing its options, its page is built.
function Update-Describes {
    foreach ($id in @($Describes.Keys)) {
        $d = $Describes[$id]
        $line = $null
        while ($d.Runner.Lines.TryDequeue([ref]$line)) {
            $d.Output.Add(($line -replace '[\x01][A-Za-z]*[\x02]', ''))
            if ($d.Output.Count -gt 8) { $d.Output.RemoveAt(0) }
        }
        if (-not $d.Failed -and -not $d.Runner.Done) { continue }
        $data = $null
        try { $data = [IO.File]::ReadAllText($d.File) | ConvertFrom-Json } catch { }
        Remove-Item -LiteralPath $d.File -ErrorAction SilentlyContinue
        if ($data -and @($data.tabs).Count) { $d.Pages.Add($data) } else { $d.Failed = $true }
        if (-not $d.Failed -and $d.Step -lt $d.Item.Steps.Count - 1) { Start-DescribeStep $d; continue }
        $Describes.Remove($id)
        $Forms[$id] = if (-not $d.Failed) { New-Form $d.Item (Join-Pages $d.Pages.ToArray()) }
                      else { @{ Item = $d.Item; Error = "Could not read the settings of this PC.`n`n$(@($d.Output | Where-Object { $_.Trim() }) -join "`n")" } }
        if ($script:Page.Id -eq $id) { Show-Page $d.Item }
    }
}

# What an option changes shows on other pages too (an app from Applications in Uninstall programs, a policy
# in Undo): when one is applied, and when it finishes, every page is dropped and read again when opened.
# Pages still being read are stopped: they could have read the PC halfway through the change.
function Reset-Pages {
    foreach ($id in @($Describes.Keys)) {
        $d = $Describes[$id]
        try { $d.Runner.Stop() } catch { }
        if ($d.File) { Remove-Item -LiteralPath $d.File -ErrorAction SilentlyContinue }
        $Describes.Remove($id)
    }
    $Forms.Clear()
}

function Get-CurrentForm { if ($script:Page) { $Forms[$script:Page.Id] } }
function Update-CurrentForm { $f = Get-CurrentForm; if ($f -and $f.Ctl) { Update-Form $f } }

function New-Grid([string[]]$Columns) {
    $g = New-Object Windows.Controls.Grid
    foreach ($c in $Columns) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = if ($c -eq 'Auto') { [Windows.GridLength]::Auto } else { New-Object Windows.GridLength 1, 'Star' }
        $g.ColumnDefinitions.Add($cd)
    }
    return $g
}

function Get-Options($Form, $Field) {
    if ($Field.parent) {
        # The options for what is picked in the parent; "current" while nothing is picked there
        $key = Get-FieldValue $Form "$($Field.parent)"
        if (-not $key) { $key = 'current' }
        $p = $Field.optionsBy.PSObject.Properties["$key"]
        if ($p) { return @($p.Value) }
    }
    return @($Field.options)
}

# Fills a select; $Value stays picked if it is still there, otherwise nothing is picked.
function Set-SelectOptions($Combo, [object[]]$Options, [string]$Value) {
    $Combo.Items.Clear()
    $pick = -1
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $it = New-Object Windows.Controls.ComboBoxItem
        $it.Content = "$($Options[$i].label)"
        $it.Tag = "$($Options[$i].value)"
        [void]$Combo.Items.Add($it)
        if ("$($Options[$i].value)" -eq $Value) { $pick = $i }
    }
    $Combo.SelectedIndex = $pick
}

# One option as a row: what it is and what it does on the left, its control on the right.
function New-FieldRow($Form, $F) {
    $id = "$($F.id)"
    $info = @{ Field = $F; Kind = "$($F.kind)" }
    $Form.Ctl[$id] = $info

    if ($F.kind -eq 'header') {
        $box = New-Object Windows.Controls.StackPanel
        $box.Margin = New-Object Windows.Thickness 0, 16, 0, 8
        $box.Children.Add((New-Text "$($F.label)" 13 'SemiBold')) | Out-Null
        if ($F.desc) { $box.Children.Add((New-Text "$($F.desc)" 12 'Normal' 'Fg2')) | Out-Null }
        $info.Row = $box
        return $box
    }

    $row = New-Object Windows.Controls.Border
    $row.Style = $W.Resources['RowBox']
    if ($F.indent) { $m = $row.Margin; $row.Margin = New-Object Windows.Thickness ($m.Left + 28), $m.Top, $m.Right, $m.Bottom }
    $text = New-Object Windows.Controls.StackPanel
    $text.VerticalAlignment = 'Center'
    # The name, with its size (or another short detail) next to it
    $name = New-Object Windows.Controls.TextBlock
    $name.TextWrapping = 'Wrap'
    $name.Inlines.Add((New-Object Windows.Documents.Run "$($F.label)"))
    if ("$($F.badge)") {
        $badge = New-Object Windows.Documents.Run "  ·  $($F.badge)"
        $badge.Foreground = $W.Resources['Fg2']; $badge.FontSize = 12
        $name.Inlines.Add($badge)
    }
    $text.Children.Add($name) | Out-Null
    foreach ($part in @(@("$($F.desc)", 'Fg2'), @("$($F.warn)", 'Warn'))) {
        if (-not $part[0]) { continue }
        $t = New-Text $part[0] 13 'Normal' $part[1]
        $t.Margin = New-Object Windows.Thickness 0, 2, 0, 0
        $text.Children.Add($t) | Out-Null
    }
    $info.Row = $row

    if ($F.kind -eq 'checklist') {
        # The items go below the text, in groups, with "Select all"
        $stack = New-Object Windows.Controls.StackPanel
        if ("$($F.label)") { $stack.Children.Add($text) | Out-Null }
        $lines = New-Object System.Collections.Generic.List[object]
        if ($F.search) {
            # Long lists (installed programs): typing hides the rows whose name doesn't have the text
            $find = New-Object Windows.Controls.Grid
            $find.Margin = New-Object Windows.Thickness 0, 0, 0, 12
            $find.Width = 320; $find.HorizontalAlignment = 'Left'
            $box = New-Object Windows.Controls.TextBox
            $hint = New-Text 'Search' 13 'Normal' 'Fg3'
            $hint.Margin = New-Object Windows.Thickness 11, 0, 0, 0
            $hint.VerticalAlignment = 'Center'; $hint.IsHitTestVisible = $false
            $box.Tag = @{ Hint = $hint; Lines = $lines }
            $box.Add_TextChanged({
                $q = $this.Text.Trim()
                $this.Tag.Hint.Visibility = if ($this.Text) { 'Collapsed' } else { 'Visible' }
                foreach ($l in $this.Tag.Lines) { $l.Line.Visibility = if (-not $q -or $l.Label.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0) { 'Visible' } else { 'Collapsed' } }
            })
            $find.Children.Add($box) | Out-Null
            $find.Children.Add($hint) | Out-Null
            $stack.Children.Add($find) | Out-Null
        }
        $info.Items = New-Object System.Collections.Generic.List[object]
        $info.Flags = New-Object System.Collections.Generic.List[object]
        $info.Groups = New-Object System.Collections.Generic.List[object]
        $defaults = @($F.default | ForEach-Object { "$_" })
        $group = $null; $wrap = $null
        foreach ($item in @($F.items)) {
            if (-not $wrap -or "$($item.group)" -ne $group) {
                $group = "$($item.group)"
                # Group name on the left, its "Select all" on the right; then one row per item
                $head = New-Object Windows.Controls.DockPanel
                $head.Margin = New-Object Windows.Thickness 0, $(if ($stack.Children.Count) { 16 } else { 0 }), 0, 6
                $link = New-Object Windows.Controls.Button
                $link.Style = $W.Resources['Link']; $link.Content = 'Select all'
                $link.VerticalAlignment = 'Center'
                if ($F.search) { $link.Visibility = 'Collapsed'; if (-not $group) { $head.Visibility = 'Collapsed' } }    # "every installed program" is never one click away
                [Windows.Controls.DockPanel]::SetDock($link, 'Right')
                $head.Children.Add($link) | Out-Null
                $head.Children.Add((New-Text $(if ($group) { $group } else { '' }) 13 'SemiBold' 'Fg2')) | Out-Null
                $wrap = New-Object Windows.Controls.StackPanel
                $stack.Children.Add($head) | Out-Null
                $stack.Children.Add($wrap) | Out-Null
                $g = @{ Link = $link; Boxes = New-Object System.Collections.Generic.List[object] }
                $link.Tag = $g
                $link.Add_Click({
                    $all = @($this.Tag.Boxes | Where-Object { -not $_.IsChecked }).Count -eq 0
                    foreach ($b in $this.Tag.Boxes) { $b.IsChecked = -not $all }
                })
                $info.Groups.Add($g)
            }
            # The name, "• Installed" next to it, and the description below
            $name = New-Object Windows.Controls.TextBlock
            $name.TextWrapping = 'Wrap'
            $name.Inlines.Add((New-Object Windows.Documents.Run "$($item.label)"))
            if ("$($item.status)") {
                $tag = New-Object Windows.Documents.Run "  •  $($item.status)"
                $tag.Foreground = $W.Resources['Ok']; $tag.FontSize = 12
                $name.Inlines.Add($tag)
            }
            $content = New-Object Windows.Controls.StackPanel
            $content.Children.Add($name) | Out-Null
            if ("$($item.note)") { $content.Children.Add((New-Text "$($item.note)" 12 'Normal' 'Fg2')) | Out-Null }
            $box = New-Object Windows.Controls.CheckBox
            $box.Content = $content
            $box.VerticalAlignment = 'Center'
            $box.Tag = "$($item.value)"
            $box.IsChecked = $defaults -contains "$($item.value)"
            $box.Add_Checked({ Update-CurrentForm })
            $box.Add_Unchecked({ Update-CurrentForm })
            $line = New-Object Windows.Controls.Border
            $line.BorderBrush = $W.Resources['Line']
            $line.BorderThickness = New-Object Windows.Thickness 0, 1, 0, 0
            $line.Padding = New-Object Windows.Thickness 0, 9, 0, 9
            $cols = New-Grid 'Star', 'Auto'
            $cols.Children.Add($box) | Out-Null
            if ($F.flagLabel) {
                # Fixed width: the second box lines up from row to row
                $slot = New-Object Windows.Controls.Grid
                $slot.Margin = New-Object Windows.Thickness 24, 0, 0, 0
                $slot.HorizontalAlignment = 'Right'
                [Windows.Controls.Grid]::SetColumn($slot, 1)
                $cols.Children.Add($slot) | Out-Null
                # Interactive: turning it on also checks the item
                if ($null -ne $item.flag) {
                    $flag = New-Object Windows.Controls.CheckBox
                    $flag.Content = New-Text "$($F.flagLabel)" 12 'Normal' 'Fg2'
                    $flag.ToolTip = "$($F.flagHint)"
                    $flag.IsChecked = [bool]$item.flag
                    $flag.VerticalAlignment = 'Center'
                    $flag.Tag = $box
                    $flag.Add_Checked({ $this.Tag.IsChecked = $true; Update-CurrentForm })
                    $flag.Add_Unchecked({ Update-CurrentForm })
                    $slot.Children.Add($flag) | Out-Null
                    $info.Flags.Add($flag)
                }
            }
            $line.Child = $cols
            $lines.Add(@{ Line = $line; Label = "$($item.label)" })
            $wrap.Children.Add($line) | Out-Null
            $info.Items.Add($box)
            $g.Boxes.Add($box)
        }
        $row.Child = $stack
        return $row
    }

    $grid = New-Grid 'Star', 'Auto'
    $grid.Children.Add($text) | Out-Null
    $control = $null
    switch ($F.kind) {
        'toggle' {
            $control = New-Object Windows.Controls.CheckBox
            $control.Style = $W.Resources['Switch']
            $control.IsChecked = [bool]$F.default
            $control.Add_Checked({ Update-CurrentForm })
            $control.Add_Unchecked({ Update-CurrentForm })
        }
        'choice' {
            $control = New-Object Windows.Controls.StackPanel
            $control.Orientation = 'Horizontal'
            foreach ($o in @($F.options)) {
                $r = New-Object Windows.Controls.RadioButton
                $r.Style = $W.Resources['Seg']
                $r.Content = "$($o.label)"
                $r.Tag = "$($o.value)"
                $r.GroupName = "$($Form.Item.Id).$id"
                $r.IsChecked = "$($F.default)" -and "$($o.value)" -eq "$($F.default)"
                $r.Add_Checked({ Update-CurrentForm })
                $r.Add_PreviewMouseLeftButtonDown({
                    if ($this.IsChecked) { $this.IsChecked = $false; $_.Handled = $true; Update-CurrentForm }
                })
                $control.Children.Add($r) | Out-Null
            }
        }
        'select' {
            $combo = New-Object Windows.Controls.ComboBox
            $combo.Width = 260
            $combo.Uid = $id
            $info.Control = $combo
            Set-SelectOptions $combo (Get-Options $Form $F) "$($F.default)"
            $combo.Add_SelectionChanged({ Update-SelectChildren $this.Uid; Update-CurrentForm })
            $hint = New-Text 'Choose' 13 'Normal' 'Fg3'
            $hint.Margin = New-Object Windows.Thickness 10, 0, 0, 0
            $hint.VerticalAlignment = 'Center'; $hint.IsHitTestVisible = $false
            $info.Hint = $hint
            $clear = New-Object Windows.Controls.Button
            $clear.Style = $W.Resources['Link']; $clear.Content = 'Clear'
            $clear.VerticalAlignment = 'Center'
            $clear.Margin = New-Object Windows.Thickness 0, 0, 12, 0
            $clear.Tag = $combo
            $clear.Add_Click({ $this.Tag.SelectedIndex = -1 })
            $info.Clear = $clear
            $box = New-Object Windows.Controls.Grid
            $box.Children.Add($combo) | Out-Null
            $box.Children.Add($hint) | Out-Null
            $control = New-Object Windows.Controls.StackPanel
            $control.Orientation = 'Horizontal'
            $control.Children.Add($clear) | Out-Null
            $control.Children.Add($box) | Out-Null
        }
        'text' {
            $control = New-Object Windows.Controls.Grid
            $control.Width = 260
            $box = New-Object Windows.Controls.TextBox
            $box.Text = "$($F.default)"
            $hint = New-Text "$($F.placeholder)" 13 'Normal' 'Fg3'
            $hint.Margin = New-Object Windows.Thickness 11, 0, 0, 0
            $hint.VerticalAlignment = 'Center'; $hint.IsHitTestVisible = $false
            $hint.Visibility = if ($box.Text) { 'Collapsed' } else { 'Visible' }
            $box.Tag = $hint
            $box.Add_TextChanged({ $this.Tag.Visibility = if ($this.Text) { 'Collapsed' } else { 'Visible' }; Update-CurrentForm })
            $control.Children.Add($box) | Out-Null
            $control.Children.Add($hint) | Out-Null
            $info.Box = $box
            $err = New-Text 'Not a valid address' 12 'Normal' 'Err'
            $err.Margin = New-Object Windows.Thickness 0, 2, 0, 0
            $err.Visibility = 'Collapsed'
            $text.Children.Add($err) | Out-Null
            $info.Error = $err
        }
        'path' {
            # A folder or a file: typed, or picked with Browse
            $field = New-Object Windows.Controls.Grid
            $field.Width = 260
            $box = New-Object Windows.Controls.TextBox
            $box.Text = "$($F.default)"
            $hint = New-Text $(if ($F.placeholder) { "$($F.placeholder)" } elseif ($F.pick -eq 'file') { 'Choose a file' } else { 'Choose a folder' }) 13 'Normal' 'Fg3'
            $hint.Margin = New-Object Windows.Thickness 11, 0, 0, 0
            $hint.VerticalAlignment = 'Center'; $hint.IsHitTestVisible = $false
            $hint.Visibility = if ($box.Text) { 'Collapsed' } else { 'Visible' }
            $box.Tag = $hint
            $box.Add_TextChanged({ $this.Tag.Visibility = if ($this.Text) { 'Collapsed' } else { 'Visible' }; Update-CurrentForm })
            $field.Children.Add($box) | Out-Null
            $field.Children.Add($hint) | Out-Null
            $browse = New-Object Windows.Controls.Button
            $browse.Style = $W.Resources['Btn']; $browse.Content = 'Browse'
            $browse.Margin = New-Object Windows.Thickness 8, 0, 0, 0
            $browse.Tag = @{ Box = $box; Field = $F }
            $browse.Add_Click({
                $box = $this.Tag.Box
                if ($this.Tag.Field.pick -eq 'file') {
                    $d = New-Object Microsoft.Win32.OpenFileDialog
                    $d.Filter = if ($this.Tag.Field.filter) { "$($this.Tag.Field.filter)" } else { 'All files (*.*)|*.*' }
                    if ($d.ShowDialog($W)) { $box.Text = $d.FileName }
                } else {
                    $d = New-Object System.Windows.Forms.FolderBrowserDialog
                    if ($box.Text -and (Test-Path -LiteralPath $box.Text)) { $d.SelectedPath = $box.Text }
                    if ($d.ShowDialog() -eq 'OK') { $box.Text = $d.SelectedPath }
                }
            })
            $control = New-Object Windows.Controls.StackPanel
            $control.Orientation = 'Horizontal'
            $control.Children.Add($field) | Out-Null
            $control.Children.Add($browse) | Out-Null
            $info.Box = $box
            $err = New-Text $(if ($F.pick -eq 'file') { 'File not found' } else { 'Folder not found' }) 12 'Normal' 'Err'
            $err.Margin = New-Object Windows.Thickness 0, 2, 0, 0
            $err.Visibility = 'Collapsed'
            $text.Children.Add($err) | Out-Null
            $info.Error = $err
        }
        'info' {
            # Only shows (the network adapters), with an optional status on the right
            $status = @{ ok = @('OK', 'Ok'); warn = @('Attention', 'Warn'); bad = @('Problem', 'Err') }["$($F.status)"]
            $control = if ($status) { New-Text $status[0] 13 'SemiBold' $status[1] } else { New-Text '' 13 }
        }
    }
    if (-not $info.Control) { $info.Control = $control }
    foreach ($r in 1, 2) { $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{ Height = [Windows.GridLength]::Auto })) }
    $grid.Children.Add($control) | Out-Null
    $grid.Tag = $control
    # With display scaling (125%...) layout rounding can make the control's column a few pixels narrower
    # than the control, which then loses its right edge: no rounding in the row.
    $grid.UseLayoutRounding = $false
    $control.UseLayoutRounding = $false
    Set-RowLayout $grid $false
    $grid.Add_SizeChanged({ Update-RowLayout $this })
    $row.Child = $grid
    return $row
}

# The control goes to the right of the text, or below it when the row is too narrow for both.
function Set-RowLayout($Grid, [bool]$Below) {
    $c = $Grid.Tag
    [Windows.Controls.Grid]::SetRow($c, [int]$Below)
    [Windows.Controls.Grid]::SetColumn($c, [int](-not $Below))
    $c.VerticalAlignment = 'Center'
    $c.HorizontalAlignment = if ($Below) { 'Left' } else { 'Right' }
    $c.Margin = if ($Below) { New-Object Windows.Thickness 0, 10, 0, 0 } else { New-Object Windows.Thickness 24, 0, 0, 0 }
}

function Update-RowLayout($Grid) {
    $c = $Grid.Tag
    $width = $c.DesiredSize.Width - $c.Margin.Left - $c.Margin.Right      # the control alone, wherever it is
    $below = ($Grid.ActualWidth - $width - 24) -lt 280                     # 280: room left for the text
    if ($below -ne ([Windows.Controls.Grid]::GetRow($c) -eq 1)) { Set-RowLayout $Grid $below }
}

# A select whose options depend on this one (refresh rates of a resolution) gets the new options.
function Update-SelectChildren([string]$ParentId) {
    $form = Get-CurrentForm
    if (-not $form -or -not $form.Ctl) { return }
    foreach ($c in @($form.Ctl.Values | Where-Object { "$($_.Field.parent)" -eq $ParentId })) {
        $keep = Get-FieldValue $form "$($c.Field.id)"
        Set-SelectOptions $c.Control (Get-Options $form $c.Field) $keep
    }
}

function Get-FieldValue($Form, [string]$Id) {
    $c = $Form.Ctl[$Id]
    if (-not $c) { return $null }
    switch ($c.Kind) {
        'toggle'    { return [bool]$c.Control.IsChecked }
        'choice'    { $r = @($c.Control.Children | Where-Object { $_.IsChecked })[0]; if ($r) { return "$($r.Tag)" }; return '' }
        'select'    { if ($c.Control.SelectedItem) { return "$($c.Control.SelectedItem.Tag)" }; return '' }
        { $_ -in 'text', 'path' } { return $c.Box.Text.Trim() }
        'checklist' { return ,@($c.Items | Where-Object { $_.IsChecked } | ForEach-Object { "$($_.Tag)" }) }
    }
    return $null
}

function Get-FlagValues($Form, [string]$Id) {
    $c = $Form.Ctl[$Id]
    return ,@($c.Flags | Where-Object { $_.IsChecked -and $_.Tag.IsChecked } | ForEach-Object { "$($_.Tag.Tag)" })
}

function Test-FieldShown($Form, $Field) {
    if (-not $Field.when) { return $true }
    return "$(Get-FieldValue $Form "$($Field.when.field)")" -eq "$($Field.when.is)"
}

function Test-FieldValid($Form, $Field) {
    if ($Field.kind -eq 'path') {
        $v = Get-FieldValue $Form "$($Field.id)"
        if (-not $v) { return -not $Field.required }
        return (Test-Path -LiteralPath $v -PathType $(if ($Field.pick -eq 'file') { 'Leaf' } else { 'Container' }))
    }
    if ($Field.kind -ne 'text') { return $true }
    $v = Get-FieldValue $Form "$($Field.id)"
    if (-not $v) { return [bool]$Field.optional }
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($v, [ref]$ip)) { return $false }
    if ($Field.validate -eq 'ipv4') { return $ip.AddressFamily -eq 'InterNetwork' -and $v -match '^\d{1,3}(\.\d{1,3}){3}$' }
    if ($Field.validate -eq 'ipv6') { return $ip.AddressFamily -eq 'InterNetworkV6' }
    return $true
}

function Get-OptionLabel($Form, $Field, [string]$Value) {
    $o = @(Get-Options $Form $Field | Where-Object { "$($_.value)" -eq $Value })[0]
    if ($o) { return ("$($o.label)" -replace ' · (current|recommended)', '') }
    return $Value
}

# What applying will do, one line per option, with its tab.
function Get-FormChanges($Form) {
    $header = @{}
    foreach ($f in $Form.Fields) {
        if (-not (Test-FieldShown $Form $f)) { continue }
        if ($f.kind -eq 'header') { $header["$($f.tab)"] = "$($f.label)"; continue }
        if ($f.quiet) { continue }      # only shows other options (Browsers: the switch of each browser)
        $value = Get-FieldValue $Form "$($f.id)"
        $label = if ($header["$($f.tab)"]) { "$($header["$($f.tab)"]) · $($f.label)" } else { "$($f.label)" }
        $text = $null
        switch ($f.kind) {
            'toggle'    { if ($value) { $text = "$($f.label)" } }
            'checklist' {
                $flagged = @(if ($f.flagLabel) { Get-FlagValues $Form "$($f.id)" })
                $names = @($f.items | Where-Object { @($value) -contains "$($_.value)" } | ForEach-Object {
                    "$($_.label)" + $(if ($flagged -contains "$($_.value)") { " ($("$($f.flagLabel)".ToLower()))" } else { '' })
                })
                if ($names) { $text = "$(if ($f.label) { $f.label } else { $f.tab }): $($names -join ', ')" }
            }
            { $_ -in 'text', 'path' } { if ($value) { $text = "${label}: $value" } }
            { $_ -in 'choice', 'select' } { if ($value) { $text = "${label}: $(Get-OptionLabel $Form $f $value)" } }
        }
        $count = if ($f.footer) { 0 } elseif ($f.kind -eq 'checklist') { @($value).Count } else { 1 }
        if ($text) { [pscustomobject]@{ Tab = $(if ($f.group) { "$($f.group)" } else { "$($f.tab)" }); Text = $text; Footer = [bool]$f.footer; Count = $count } }
    }
}

# After any change: what is shown, wrong addresses, the "Select all" links and the count at the bottom.
function Update-Form($Form) {
    foreach ($f in $Form.Fields) {
        $c = $Form.Ctl["$($f.id)"]
        $shown = Test-FieldShown $Form $f
        $c.Row.Visibility = if ($shown) { 'Visible' } else { 'Collapsed' }
        if ($c.Error) { $c.Error.Visibility = if ($shown -and $c.Box.Text.Trim() -and -not (Test-FieldValid $Form $f)) { 'Visible' } else { 'Collapsed' } }
        if ($c.Hint) {
            $picked = $c.Control.SelectedIndex -ge 0
            $c.Hint.Visibility = if ($picked) { 'Collapsed' } else { 'Visible' }
            $c.Clear.Visibility = if ($picked) { 'Visible' } else { 'Hidden' }
        }
        if ($c.Groups) {
            foreach ($g in $c.Groups) { $g.Link.Content = if (@($g.Boxes | Where-Object { -not $_.IsChecked }).Count) { 'Select all' } else { 'Clear' } }
        }
    }
    $Form.Changes = @(Get-FormChanges $Form)
    if ($script:Page.Id -eq $Form.Item.Id -and $Form.View -eq 'form' -and $ui.FormView.Visibility -eq 'Visible') { Update-FormFooter $Form }
}

function Update-FormFooter($Form) {
    # What is picked: a checklist counts each item (3 programs, 3); the footer option doesn't count
    $n = [int]($Form.Changes | Measure-Object Count -Sum).Sum
    $ui.Status.Foreground = $W.Resources['Fg2']
    $ui.Status.Text = if ($S.Active) { "Wait for $($S.Item.Title) to finish before applying." }
                      elseif ($n -eq 0) { 'Nothing selected' } else { "$n selected" }
    # The footer option only goes with something else (leftovers without programs do nothing)
    $ui.ReviewBtn.IsEnabled = @($Form.Changes | Where-Object { -not $_.Footer }).Count -gt 0 -and -not $S.Active
    $ui.ApplyBtn.IsEnabled = -not $S.Active
}

function New-Form($Item, $Data) {
    $form = @{ Item = $Item; Fields = @($Data.fields); Tabs = @($Data.tabs); Ctl = @{}; Panels = @{}; Stacks = @{}; Tab = $null; View = 'form'; Changes = @(); Built = Get-Date }
    foreach ($tab in $form.Tabs) {
        # The rows take the whole width up to 900, on the left: a column with MaxWidth (a panel with
        # MaxWidth would be centered, and one aligned left would shrink to its content)
        $holder = New-Object Windows.Controls.Grid
        $column = New-Object Windows.Controls.ColumnDefinition
        $column.Width = New-Object Windows.GridLength 1, 'Star'
        $column.MaxWidth = 900
        $holder.ColumnDefinitions.Add($column)
        $holder.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = [Windows.GridLength]::Auto }))
        $panel = New-Object Windows.Controls.StackPanel
        $panel.Margin = New-Object Windows.Thickness 0, 0, 14, 8
        $holder.Children.Add($panel) | Out-Null
        $form.Panels[$tab] = $holder
        $form.Stacks[$tab] = $panel
    }
    foreach ($note in @($Data.notes)) {
        if (-not $note) { continue }
        $t = New-Text "$note" 12 'Normal' 'Warn'
        $t.Margin = New-Object Windows.Thickness 0, 0, 0, 10
        $form.Stacks[$form.Tabs[0]].Children.Add($t) | Out-Null
    }
    foreach ($f in $form.Fields) {
        if ($f.footer) {
            # A page's one extra option (Uninstall: the leftovers), next to the buttons: no scrolling to reach it
            $box = New-Object Windows.Controls.CheckBox
            $box.Content = New-Text "$($f.label)" 13
            $box.ToolTip = "$($f.desc)"
            $box.IsChecked = [bool]$f.default
            $box.Add_Checked({ Update-CurrentForm })
            $box.Add_Unchecked({ Update-CurrentForm })
            $form.Ctl["$($f.id)"] = @{ Field = $f; Kind = 'toggle'; Control = $box; Row = $box }
            $form.Footer = $box
            continue
        }
        $form.Stacks["$($f.tab)"].Children.Add((New-FieldRow $form $f)) | Out-Null
    }
    $form.Tab = $form.Tabs[0]
    Update-Form $form
    return $form
}

function Show-Form($Form) {
    $Form.View = 'form'
    $ui.Tabs.Children.Clear()
    foreach ($tab in $Form.Tabs) {
        $r = New-Object Windows.Controls.RadioButton
        $r.Style = $W.Resources['Tab']
        $r.Content = $tab; $r.Tag = $tab; $r.GroupName = 'tabs'
        $r.Margin = New-Object Windows.Thickness 0, 0, 0, 4
        $r.IsChecked = $tab -eq $Form.Tab
        $r.Add_Checked({
            $f = Get-CurrentForm
            $f.Tab = $this.Tag
            $ui.FormScroll.Content = $f.Panels[$this.Tag]
            $ui.FormScroll.ScrollToTop()
        })
        $ui.Tabs.Children.Add($r) | Out-Null
    }
    $ui.Tabs.Visibility = if ($Form.Tabs.Count -gt 1) { 'Visible' } else { 'Collapsed' }
    $ui.FormScroll.Content = $Form.Panels[$Form.Tab]
    Set-View 'form'
    $ui.FooterSlot.Content = $Form.Footer
    $ui.FooterSlot.Visibility = if ($Form.Footer) { 'Visible' } else { 'Collapsed' }
    Update-Form $Form
}

function Show-Review($Form) {
    $Form.View = 'review'
    $ui.ReviewList.Children.Clear()
    $intro = New-Text 'Nothing has changed yet. When you apply:' 13 'Normal' 'Fg2'
    $intro.Margin = New-Object Windows.Thickness 0, 0, 0, 12
    $ui.ReviewList.Children.Add($intro) | Out-Null
    foreach ($group in @($Form.Changes | Group-Object Tab)) {
        $card = New-Card
        $card.Margin = New-Object Windows.Thickness 0, 0, 0, 8
        $stack = New-Object Windows.Controls.StackPanel
        $title = New-Text $group.Name 14 'SemiBold'
        $title.Margin = New-Object Windows.Thickness 0, 0, 0, 6
        $stack.Children.Add($title) | Out-Null
        foreach ($c in $group.Group) {
            $row = New-Object Windows.Controls.DockPanel
            $row.Margin = New-Object Windows.Thickness 0, 2, 0, 2
            $bullet = New-Text '•' 13 'Normal' 'Accent'
            $bullet.Margin = New-Object Windows.Thickness 0, 0, 10, 0
            $row.Children.Add($bullet) | Out-Null
            $row.Children.Add((New-Text $c.Text)) | Out-Null
            $stack.Children.Add($row) | Out-Null
        }
        $card.Child = $stack
        $ui.ReviewList.Children.Add($card) | Out-Null
    }
    if ($Form.Item.ApplyNote) {
        $note = New-Text $Form.Item.ApplyNote 13 'Normal' 'Fg2'
        $note.Margin = New-Object Windows.Thickness 0, 8, 0, 0
        $ui.ReviewList.Children.Add($note) | Out-Null
    }
    Set-View 'review'
    $n = $Form.Changes.Count
    $ui.Status.Text = if ($n -eq 1) { '1 change' } else { "$n changes" }
    $ui.Status.Foreground = $W.Resources['Fg2']
    $ui.ApplyBtn.IsEnabled = -not $S.Active
}

# Review: wrong addresses first (the page opens on their tab)
function Invoke-Review {
    $form = Get-CurrentForm
    $bad = @($form.Fields | Where-Object { (Test-FieldShown $form $_) -and -not (Test-FieldValid $form $_) })[0]
    if ($bad) {
        $form.Tab = "$($bad.tab)"
        Show-Form $form
        $ui.Status.Text = "Check $($bad.label)."
        $ui.Status.Foreground = $W.Resources['Err']
        [void]$form.Ctl["$($bad.id)"].Box.Focus()
        return
    }
    Show-Review $form
}

# Apply: the answers go to a file and the script runs with it; the page is read again afterwards.
function Invoke-Apply {
    $form = Get-CurrentForm
    if ($S.Active -or -not $form) { return }
    $answers = [ordered]@{}
    foreach ($f in $form.Fields) {
        if ($f.kind -in 'header', 'info') { continue }
        $answers["$($f.id)"] = Get-FieldValue $form "$($f.id)"
        if ($f.flagLabel) { $answers["$($f.id).flags"] = Get-FlagValues $form "$($f.id)" }
    }
    $file = Join-Path $env:TEMP "tidywin-$($form.Item.Id)-answers.json"
    [IO.File]::WriteAllText($file, (ConvertTo-Json $answers -Depth 5), (New-Object Text.UTF8Encoding $false))
    $S.AnswersFile = $file
    Reset-Pages
    Start-Item $form.Item "-Answers '$($file -replace "'", "''")'"
}

#endregion


#region ==================== 7. PAGES ====================

$Nav = @{}

function Build-Nav {
    $last = $null
    foreach ($item in $Menu) {
        if ($item.Group -ne $last) {
            $h = New-Text $item.Group 12.5 'SemiBold' 'Fg2'
            $h.Margin = New-Object Windows.Thickness 12, $(if ($last) { 18 } else { 4 }), 0, 4
            $ui.Nav.Children.Add($h) | Out-Null
            $last = $item.Group
        }
        $g = New-Object Windows.Controls.Grid
        foreach ($size in 'Auto', 'Star', 'Auto') {
            $cd = New-Object Windows.Controls.ColumnDefinition
            $cd.Width = if ($size -eq 'Auto') { [Windows.GridLength]::Auto } else { New-Object Windows.GridLength 1, 'Star' }
            $g.ColumnDefinitions.Add($cd)
        }
        $icon = New-Object Windows.Controls.TextBlock
        $icon.Text = $item.Icon
        $icon.FontFamily = New-Object Windows.Media.FontFamily 'Segoe Fluent Icons, Segoe MDL2 Assets'
        $icon.FontSize = 14; $icon.VerticalAlignment = 'Center'
        $name = New-Text $item.Name
        $name.TextWrapping = 'NoWrap'; $name.TextTrimming = 'CharacterEllipsis'
        $name.Margin = New-Object Windows.Thickness 12, 0, 0, 0
        [Windows.Controls.Grid]::SetColumn($name, 1)
        $dot = New-Object Windows.Shapes.Ellipse
        $dot.Width = 7; $dot.Height = 7; $dot.Fill = $W.Resources['Accent']; $dot.Visibility = 'Collapsed'
        $dot.VerticalAlignment = 'Center'; $dot.ToolTip = 'Running'
        [Windows.Controls.Grid]::SetColumn($dot, 2)
        $g.Children.Add($icon) | Out-Null; $g.Children.Add($name) | Out-Null; $g.Children.Add($dot) | Out-Null
        $b = New-Object Windows.Controls.Button
        $b.Style = $W.Resources['Nav']
        $b.Content = $g
        $b.Uid = $item.Id
        $b.Add_Click({ Show-Page ($Menu | Where-Object Id -eq $this.Uid) })
        $ui.Nav.Children.Add($b) | Out-Null
        $Nav[$item.Id] = @{ Button = $b; Dot = $dot }
    }
}

function Set-NavBusy([string]$Id, [bool]$Busy) {
    $Nav[$Id].Dot.Visibility = if ($Busy) { 'Visible' } else { 'Collapsed' }
}

# Shows one part of the page: intro (points and button), loading, form (options), review or run (log).
function Set-View([string]$View) {
    $ui.Intro.Visibility      = if ($View -eq 'intro') { 'Visible' } else { 'Collapsed' }
    $ui.Loading.Visibility    = 'Collapsed'                # only for an error, shown by Show-Page
    $ui.Spinner.Visibility    = if ($View -eq 'loading') { 'Visible' } else { 'Collapsed' }
    $ui.FormView.Visibility   = if ($View -eq 'form') { 'Visible' } else { 'Collapsed' }
    $ui.ReviewView.Visibility = if ($View -eq 'review') { 'Visible' } else { 'Collapsed' }
    $ui.Run.Visibility        = if ($View -eq 'run') { 'Visible' } else { 'Collapsed' }
    $ui.Footer.Visibility     = if ($View -in 'form', 'review', 'run') { 'Visible' } else { 'Collapsed' }
    foreach ($name in 'CopyBtn', 'StopBtn', 'DoneBtn') { if ($View -ne 'run') { $ui[$name].Visibility = 'Collapsed' } }
    if ($View -eq 'run') { $ui.CopyBtn.Visibility = 'Visible' }
    $ui.RetryBtn.Visibility  = 'Collapsed'
    $ui.FooterSlot.Visibility = 'Collapsed'; $ui.FooterSlot.Content = $null
    $ui.ReviewBtn.Visibility = if ($View -eq 'form') { 'Visible' } else { 'Collapsed' }
    $ui.BackBtn.Visibility   = if ($View -eq 'review') { 'Visible' } else { 'Collapsed' }
    $ui.ApplyBtn.Visibility  = if ($View -eq 'review') { 'Visible' } else { 'Collapsed' }
}

# The page of an option. The option running (or that has just run) shows its log; options with -Form show
# every option of the script; the others what they do and their button.
function Show-Page($Item) {
    $script:Page = $Item
    foreach ($n in $Nav.Values) { $n.Button.Tag = $null }
    $Nav[$Item.Id].Button.Tag = 'on'
    $ui.PageTitle.Text = $Item.Title

    if ($S.Item -and $S.Item.Id -eq $Item.Id) {
        Set-View 'run'
        Update-Footer
        return
    }
    if ($Item.Form) {
        $form = $Forms[$Item.Id]
        # Read again when opened after a while with nothing picked: some installers (Figma, Discord) finish in the
        # background, after the option that ran them is done. A page with choices on it is kept as it is.
        if ($form -and -not $form.Error -and $form.View -eq 'form' -and -not $form.Changes.Count -and ((Get-Date) - $form.Built).TotalSeconds -gt 30) {
            $Forms.Remove($Item.Id); $form = $null
        }
        if (-not $form) {
            if (-not $Describes.ContainsKey($Item.Id)) { Start-Describe $Item }
            Set-View 'loading'
        } elseif ($form.Error) {
            $ui.Loading.Text = $form.Error
            $ui.Loading.Foreground = $W.Resources['Err']
            Set-View 'loading'
            $ui.Spinner.Visibility = 'Collapsed'; $ui.Loading.Visibility = 'Visible'
            $ui.Footer.Visibility = 'Visible'; $ui.RetryBtn.Visibility = 'Visible'; $ui.Status.Text = ''
        } elseif ($form.View -eq 'review') { Show-Review $form }
        else { Show-Form $form }
        return
    }

    Set-View 'intro'
    $ui.Points.Children.Clear()
    foreach ($point in $Item.Points) {
        $row = New-Object Windows.Controls.DockPanel
        $row.Margin = New-Object Windows.Thickness 0, 3, 0, 3
        $bullet = New-Text '•' 13 'Normal' 'Accent'
        $bullet.Margin = New-Object Windows.Thickness 0, 0, 10, 0
        $row.Children.Add($bullet) | Out-Null
        $row.Children.Add((New-Text $point)) | Out-Null
        $ui.Points.Children.Add($row) | Out-Null
    }
    $ui.StartBtn.Content = $Item.Action
    $busy = [bool]$S.Active
    $ui.StartBtn.IsEnabled = -not $busy
    $ui.IntroNote.Text = if ($busy) { "Wait for $($S.Item.Title) to finish, or stop it." } else { 'Nothing changes until you confirm.' }
}

#endregion


#region ==================== 8. START ====================

try { [void][TidyWinPanel.Native]::SetCurrentProcessExplicitAppUserModelID('androksi.TidyWin') } catch { }   # its own taskbar icon

$Theme = Get-Theme
$text = $Xaml
foreach ($k in $Theme.Keys) { $text = $text.Replace("%$k%", "$($Theme[$k])") }
$W = [Windows.Markup.XamlReader]::Parse($text)

$ui = @{}
foreach ($name in 'Logo', 'OsLabel', 'Nav', 'PageTitle', 'Intro', 'Points', 'StartBtn', 'IntroNote', 'Run',
                  'QuestionRow', 'LogRow', 'Question', 'Log', 'Footer', 'Status', 'CopyBtn', 'StopBtn', 'DoneBtn',
                  'Loading', 'Spinner', 'FormView', 'Tabs', 'FormScroll', 'ReviewView', 'ReviewList', 'RetryBtn', 'BackBtn', 'ReviewBtn', 'ApplyBtn', 'FooterSlot') {
    $ui[$name] = $W.FindName($name)
}

# Fits small screens (a laptop at 125% has about 1100 x 600 to spare)
$area = [Windows.SystemParameters]::WorkArea
$W.Width  = [Math]::Min($W.Width, $area.Width - 40)
$W.Height = [Math]::Min($W.Height, $area.Height - 40)
$W.MinHeight = [Math]::Min($W.MinHeight, $W.Height)

try { $logo = New-Logo 64; $ui.Logo.Source = $logo; $W.Icon = $logo } catch { }
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
$osName = "$($cv.ProductName)" -replace '^Microsoft\s+', ''
if ([int]$cv.CurrentBuild -ge 22000) { $osName = $osName -replace 'Windows 10', 'Windows 11' }   # Windows 11 still says 10 here
$ui.OsLabel.Text = "$osName $($cv.DisplayVersion)".Trim()

$Menu = @(Get-Menu)
($Menu | Where-Object Id -eq 'windows') | Add-Member ApplyNote 'A restore point is created first, and a log of everything is saved on your Desktop.'
Build-Nav
$ui.Log.Document = New-LogDocument

$ui.StartBtn.Add_Click({ if (-not $S.Active) { Start-Item $script:Page } })
$ui.StopBtn.Add_Click({
    $answer = [Windows.MessageBox]::Show($W, "Stop $($S.Item.Title)? A change in progress may be left half done.", 'TidyWin', 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }
    if ($S.Running) { Stop-Run }                       # the timer finishes it when the script has ended
    else { $S.Stopped = $true; Complete-Item }         # between two steps: nothing is running
})
$ui.DoneBtn.Add_Click({ $done = $S.Item; $S.Item = $null; Show-Page $done })
$ui.CopyBtn.Add_Click({
    $range = New-Object Windows.Documents.TextRange $ui.Log.Document.ContentStart, $ui.Log.Document.ContentEnd
    try { [Windows.Clipboard]::SetText($range.Text); $ui.CopyBtn.Content = 'Copied' } catch { }
})
$ui.CopyBtn.Add_MouseLeave({ $ui.CopyBtn.Content = 'Copy log' })
$ui.ReviewBtn.Add_Click({ Invoke-Review })
$ui.BackBtn.Add_Click({ Show-Form (Get-CurrentForm) })
$ui.ApplyBtn.Add_Click({ Invoke-Apply })
$ui.RetryBtn.Add_Click({ $Forms.Remove($script:Page.Id); Show-Page $script:Page })

$W.Add_SourceInitialized({
    if (-not $Theme.Light) { try { [TidyWinPanel.Native]::DarkTitleBar((New-Object Windows.Interop.WindowInteropHelper $W).Handle) } catch { } }
})
$W.Add_ContentRendered({ $W.Topmost = $true; $W.Activate() | Out-Null; $W.Topmost = $false })   # in front of the terminal
$W.Add_Closing({
    param($sender, $e)
    if ($S.Active) {
        $answer = [Windows.MessageBox]::Show($W, "$($S.Item.Title) is still running. Stop it and close TidyWin?", 'TidyWin', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { $e.Cancel = $true; return }
        Stop-Run
    }
    $timer.Stop()
})
$W.Dispatcher.Add_UnhandledException({
    param($sender, $e)
    $e.Handled = $true
    [void][Windows.MessageBox]::Show($W, "Something went wrong in the panel: $($e.Exception.Message)", 'TidyWin', 'OK', 'Error')
})

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(70)
$timer.Add_Tick({ try { Update-Run } catch { Add-LogLine ([string][char]1 + 'Red' + [char]2 + "Panel error: $($_.Exception.Message)") } })
$timer.Start()

Show-Page $Menu[0]
[void]$W.ShowDialog()

#endregion
