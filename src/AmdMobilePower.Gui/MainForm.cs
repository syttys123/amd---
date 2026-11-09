using System.Globalization;
using System.Text.RegularExpressions;
using AmdMobilePower.Core.Contracts;
using AmdMobilePower.Core.Diagnostics;
using AmdMobilePower.Core.Models;
using AmdMobilePower.Gui.Ui;

namespace AmdMobilePower.Gui;

internal sealed class MainForm : Form
{
    private readonly EventWaitHandle _showEvent;
    private readonly bool _startHidden;
    private readonly bool _writeControlsEnabled;
    private readonly WorkerProcessController _worker;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly System.Windows.Forms.Timer _refreshTimer;
    private readonly Icon _appIcon;
    private readonly Icon _trayIcon;
    private readonly Image? _headerImage;
    private readonly NumericEntry[] _limitInputs = new NumericEntry[3];
    private readonly Button[] _presetButtons = new Button[3];
    private readonly Button[] _simplePresetButtons = new Button[3];
    private readonly List<ToolStripMenuItem> _trayPresetItems = new(3);
    private StoredPowerPolicy? _storedPolicy;

    private NotifyIcon _notifyIcon = null!;
    private ContextMenuStrip _trayMenu = null!;
    private ToolStripMenuItem _trayStatusItem = null!;
    private ToolStripMenuItem _traySimpleModeItem = null!;
    private ToolStripMenuItem _trayAdvancedModeItem = null!;
    private ToolStripMenuItem _trayTopMostItem = null!;
    private TableLayoutPanel _rootLayout = null!;
    private Panel _headerHost = null!;
    private PictureBox _headerIcon = null!;
    private Label _headerTitle = null!;
    private Panel _headerModeSwitch = null!;
    private Panel _bodyHost = null!;
    private Panel _footerHost = null!;
    private Control _advancedBody = null!;
    private Control _simpleBody = null!;
    private Button _simpleModeButton = null!;
    private Button _advancedModeButton = null!;
    private Button _topMostButton = null!;
    private Label _connectionBadge = null!;
    private Label _headerPlatform = null!;
    private Label _currentPower = null!;
    private Label _powerLineBadge = null!;
    private Label _profileValue = null!;
    private Label _rangeValue = null!;
    private Label _stapmValue = null!;
    private Label _fastValue = null!;
    private Label _slowValue = null!;
    private Label _temperatureValue = null!;
    private Label _statusLabel = null!;
    private Label _updatedLabel = null!;
    private Label _writeStateLabel = null!;
    private Label _policyStatusLabel = null!;
    private PowerUsageBar _powerBar = null!;
    private Button _applyButton = null!;
    private Button _diagnosticsButton = null!;
    private Button _editPresetButton = null!;
    private Label _simpleCurrentPower = null!;
    private Label _simplePowerLineBadge = null!;
    private Label _simpleStapmValue = null!;
    private Label _simpleFastValue = null!;
    private Label _simpleSlowValue = null!;
    private Label _simpleTemperatureValue = null!;
    private Label _simpleStapmLimitValue = null!;
    private Label _simpleFastLimitValue = null!;
    private Label _simpleSlowLimitValue = null!;
    private Label _simpleTemperatureLimitValue = null!;
    private Label _simpleRangeLabel = null!;
    private Label _simpleLimitSummary = null!;
    private Label _simpleStatusLabel = null!;
    private Label _simpleWriteStateLabel = null!;
    private TableLayoutPanel _simpleStatusBar = null!;
    private readonly SimpleMetricTile[] _simpleMetricTiles = new SimpleMetricTile[4];
    private PowerUsageBar _simplePowerBar = null!;
    private NumericEntry _simpleTargetInput = null!;
    private Button _simpleApplyButton = null!;
    private Button _simpleEditPresetButton = null!;
    private Button _savePolicyButton = null!;
    private CheckBox _autoPolicyCheckBox = null!;
    private NumericEntry _batteryPolicyInput = null!;
    private NumericEntry _acPolicyInput = null!;
    private int[] _presets = UiStateStore.LoadPresets();
    private WorkerSnapshot? _lastSnapshot;
    private bool _inputsInitialized;
    private bool _policyInputsInitialized;
    private bool _storedPolicyRestored;
    private bool _refreshing;
    private bool _connected;
    private bool _applying;
    private bool _trayHintShown;
    private bool _exitRequested;
    private bool _syncingTargets;
    private UiMode _uiMode = UiStateStore.LoadUiMode();
    private bool _topMost = UiStateStore.LoadTopMost();

    public MainForm(
        EventWaitHandle showEvent,
        bool startHidden,
        bool writeControlsEnabled)
    {
        _showEvent = showEvent;
        _startHidden = startHidden;
        _writeControlsEnabled = writeControlsEnabled;
        _worker = new WorkerProcessController(writeControlsEnabled);
        _storedPolicy = UiStateStore.LoadPowerPolicy();
        _appIcon = LoadApplicationIcon();
        _trayIcon = new Icon(_appIcon, SystemInformation.SmallIconSize);
        _headerImage = LoadHeaderImage();

        BuildWindow();
        BuildTray();
        StartShowListener();

        _refreshTimer = new System.Windows.Forms.Timer
        {
            Interval = 1000,
            Enabled = false
        };
        _refreshTimer.Tick += async delegate
        {
            await RefreshSnapshotAsync(manual: false);
        };
    }

    protected override void OnShown(EventArgs eventArgs)
    {
        base.OnShown(eventArgs);
        BeginInvoke(ApplyDpiCompensatedWindowSize);
        if (_startHidden)
        {
            BeginInvoke(HideToTray);
        }

        _refreshTimer.Start();
        _ = RefreshSnapshotAsync(manual: false);
    }

    protected override void WndProc(ref Message message)
    {
        const int WmClose = 0x0010;
        if (message.Msg == WmClose && !_exitRequested)
        {
            BeginInvoke(HideToTray);
            return;
        }

        base.WndProc(ref message);
    }

    protected override void OnFormClosing(FormClosingEventArgs eventArgs)
    {
        if (!_exitRequested)
        {
            eventArgs.Cancel = true;
            BeginInvoke(HideToTray);
            return;
        }

        base.OnFormClosing(eventArgs);
    }

    protected override void OnFormClosed(FormClosedEventArgs eventArgs)
    {
        _refreshTimer.Stop();
        _refreshTimer.Dispose();
        _lifetime.Cancel();
        _worker.DisposeAsync().AsTask().GetAwaiter().GetResult();
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _trayMenu.Dispose();
        _trayIcon.Dispose();
        _appIcon.Dispose();
        _headerImage?.Dispose();
        _lifetime.Dispose();
        base.OnFormClosed(eventArgs);
    }

    private void BuildWindow()
    {
        Text = "AMD Mobile Power";
        Icon = _appIcon;
        ShowIcon = _uiMode == UiMode.Advanced;
        FormBorderStyle = _uiMode == UiMode.Simple
            ? FormBorderStyle.FixedSingle
            : FormBorderStyle.Sizable;
        MaximizeBox = _uiMode == UiMode.Advanced;
        TopMost = _topMost;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = _uiMode == UiMode.Simple
            ? new Size(560, 400)
            : new Size(1000, 700);
        MinimumSize = _uiMode == UiMode.Simple
            ? Size.Empty
            : new Size(900, 650);
        BackColor = AppTheme.Background;
        ForeColor = AppTheme.Text;
        Font = AppTheme.Body;
        AutoScaleDimensions = new SizeF(96F, 96F);
        AutoScaleMode = AutoScaleMode.Dpi;
        DoubleBuffered = true;

        TableLayoutPanel root = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            BackColor = AppTheme.Background,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(
            SizeType.Absolute,
            _uiMode == UiMode.Simple ? 52 : 82));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(
            SizeType.Absolute,
            _uiMode == UiMode.Simple ? 0 : 34));
        _rootLayout = root;
        Controls.Add(root);

        root.Controls.Add(BuildHeader(), 0, 0);
        _bodyHost = new Panel
        {
            Dock = DockStyle.Fill,
            BackColor = AppTheme.Background,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        _advancedBody = BuildAdvancedBody();
        _simpleBody = BuildSimpleModeBody();
        _bodyHost.Controls.Add(_advancedBody);
        _bodyHost.Controls.Add(_simpleBody);
        _advancedBody.Visible = _uiMode == UiMode.Advanced;
        _simpleBody.Visible = _uiMode == UiMode.Simple;
        if (_uiMode == UiMode.Simple)
        {
            _simpleBody.BringToFront();
        }
        else
        {
            _advancedBody.BringToFront();
        }
        root.Controls.Add(_bodyHost, 0, 1);
        _footerHost = (Panel)BuildFooter();
        _footerHost.Visible = _uiMode == UiMode.Advanced;
        root.Controls.Add(_footerHost, 0, 2);
        UpdateDisplayModeControls();

        Resize += delegate
        {
            if (WindowState == FormWindowState.Minimized)
            {
                HideToTray();
            }
        };
        KeyDown += delegate (object? sender, KeyEventArgs eventArgs)
        {
            if (eventArgs.KeyCode == Keys.Escape)
            {
                HideToTray();
            }
        };
    }

    private Control BuildHeader()
    {
        Panel header = new()
        {
            Dock = DockStyle.Fill,
            BackColor = AppTheme.Header,
            Padding = new Padding(24, 14, 24, 12)
        };
        _headerHost = header;

        _headerIcon = new PictureBox
        {
            Location = new Point(24, 17),
            Size = new Size(48, 48),
            SizeMode = PictureBoxSizeMode.Zoom,
            Image = _headerImage,
            BackColor = Color.Transparent
        };
        header.Controls.Add(_headerIcon);

        _headerTitle = AppTheme.CreateLabel(
            "AMD Mobile Power",
            AppTheme.Title,
            Color.White);
        _headerTitle.Location = new Point(86, 12);
        _headerTitle.Size = new Size(Math.Max(180, header.Width - 380), 30);
        _headerTitle.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        header.Controls.Add(_headerTitle);

        _headerPlatform = AppTheme.CreateLabel(
            "正在读取平台...",
            AppTheme.Small,
            AppTheme.HeaderMuted);
        _headerPlatform.Location = new Point(88, 43);
        _headerPlatform.Size = new Size(Math.Max(180, header.Width - 380), 22);
        _headerPlatform.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        header.Controls.Add(_headerPlatform);

        _headerModeSwitch = new Panel
        {
            Size = new Size(116, 32),
            Location = new Point(Math.Max(24, header.Width - 270), 24),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            BackColor = Color.FromArgb(48, 64, 61),
            Padding = new Padding(1)
        };
        _simpleModeButton = CreateHeaderModeButton("简洁");
        _simpleModeButton.Location = new Point(1, 1);
        _simpleModeButton.Click += delegate { SwitchDisplayMode(UiMode.Simple); };
        _headerModeSwitch.Controls.Add(_simpleModeButton);
        _advancedModeButton = CreateHeaderModeButton("高级");
        _advancedModeButton.Location = new Point(59, 1);
        _advancedModeButton.Click += delegate { SwitchDisplayMode(UiMode.Advanced); };
        _headerModeSwitch.Controls.Add(_advancedModeButton);
        header.Controls.Add(_headerModeSwitch);

        _topMostButton = CreateHeaderModeButton("置顶");
        _topMostButton.AccessibleName = "窗口置顶";
        _topMostButton.Click += delegate { ToggleTopMost(); };
        header.Controls.Add(_topMostButton);

        _connectionBadge = AppTheme.CreateLabel(
            "等待 worker",
            AppTheme.SmallBold,
            Color.White,
            ContentAlignment.MiddleCenter);
        _connectionBadge.Size = new Size(118, 32);
        _connectionBadge.Location = new Point(Math.Max(24, header.Width - 142), 24);
        _connectionBadge.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _connectionBadge.BackColor = Color.FromArgb(56, 74, 71);
        header.Controls.Add(_connectionBadge);
        header.Resize += delegate { LayoutHeader(); };

        return header;
    }

    private Control BuildAdvancedBody()
    {
        TableLayoutPanel body = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            BackColor = AppTheme.Background,
            Padding = new Padding(24, 22, 24, 18)
        };
        body.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 58));
        body.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 42));
        body.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        CardPanel snapshotCard = new()
        {
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 0, 10, 0)
        };
        snapshotCard.Controls.Add(BuildSnapshotContent());

        CardPanel controlCard = new()
        {
            Dock = DockStyle.Fill,
            Margin = new Padding(10, 0, 0, 0)
        };
        controlCard.Controls.Add(BuildControlContent());

        body.Controls.Add(snapshotCard, 0, 0);
        body.Controls.Add(controlCard, 1, 0);
        return body;
    }

    private Control BuildSimpleModeBody()
    {
        Panel body = new()
        {
            Dock = DockStyle.Fill,
            BackColor = AppTheme.Surface,
            Padding = new Padding(12)
        };
        body.Controls.Add(BuildSimpleWorkspace());
        return body;
    }

    private Control BuildSimpleWorkspace()
    {
        TableLayoutPanel page = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 7,
            BackColor = Color.Transparent,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 84));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 10));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 10));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 134));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 10));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));

        page.Controls.Add(BuildSimpleHero(), 0, 0);
        page.Controls.Add(BuildSimplePresetStrip(), 0, 2);
        page.Controls.Add(BuildSimpleTelemetryMatrix(), 0, 4);
        page.Controls.Add(BuildSimpleStatusBar(), 0, 6);
        UpdateApplyButtonText();
        UpdatePresetSelection();
        return page;
    }

    private Control BuildSimpleHero()
    {
        TableLayoutPanel hero = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 1,
            BackColor = Color.Transparent,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        hero.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 184));
        hero.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 16));
        hero.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        hero.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        TableLayoutPanel live = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            BackColor = Color.Transparent,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        live.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
        live.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
        live.RowStyles.Add(new RowStyle(SizeType.Absolute, 18));

        TableLayoutPanel liveHeading = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 1,
            BackColor = Color.Transparent,
            Margin = Padding.Empty
        };
        liveHeading.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        Label liveCaption = AppTheme.CreateLabel(
            "STAPM 实时",
            AppTheme.Small,
            AppTheme.TextMuted);
        liveCaption.Dock = DockStyle.Fill;
        liveCaption.Margin = Padding.Empty;
        liveCaption.AutoEllipsis = false;
        liveHeading.Controls.Add(liveCaption, 0, 0);
        live.Controls.Add(liveHeading, 0, 0);

        TableLayoutPanel liveValues = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 1,
            BackColor = Color.Transparent,
            Margin = Padding.Empty
        };
        liveValues.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        _simpleCurrentPower = AppTheme.CreateLabel(
            "--",
            AppTheme.MetricDisplay,
            AppTheme.Accent);
        _simpleCurrentPower.Dock = DockStyle.Fill;
        _simpleCurrentPower.TextAlign = ContentAlignment.MiddleLeft;
        _simpleCurrentPower.Margin = Padding.Empty;
        _simpleCurrentPower.AutoEllipsis = false;
        liveValues.Controls.Add(_simpleCurrentPower, 0, 0);
        live.Controls.Add(liveValues, 0, 1);

        _simpleLimitSummary = AppTheme.CreateLabel(
            "动态上限 -- W",
            AppTheme.Small,
            AppTheme.TextMuted);
        _simpleLimitSummary.Dock = DockStyle.Fill;
        _simpleLimitSummary.Margin = Padding.Empty;
        _simpleLimitSummary.AutoEllipsis = false;
        live.Controls.Add(_simpleLimitSummary, 0, 2);
        hero.Controls.Add(live, 0, 0);

        TableLayoutPanel target = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            BackColor = Color.Transparent,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        target.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
        target.RowStyles.Add(new RowStyle(SizeType.Absolute, 60));

        TableLayoutPanel targetHeading = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            BackColor = Color.Transparent,
            Margin = Padding.Empty
        };
        targetHeading.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        targetHeading.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 78));
        Label targetLabel = AppTheme.CreateLabel(
            "目标功耗",
            AppTheme.BodyBold,
            AppTheme.Text);
        targetLabel.Dock = DockStyle.Fill;
        targetLabel.Margin = Padding.Empty;
        targetLabel.AutoEllipsis = false;
        targetHeading.Controls.Add(targetLabel, 0, 0);
        _simpleRangeLabel = AppTheme.CreateLabel(
            "5-60 W",
            AppTheme.Small,
            AppTheme.TextMuted,
            ContentAlignment.MiddleRight);
        _simpleRangeLabel.Dock = DockStyle.Fill;
        _simpleRangeLabel.Margin = Padding.Empty;
        _simpleRangeLabel.AutoEllipsis = false;
        targetHeading.Controls.Add(_simpleRangeLabel, 1, 0);
        target.Controls.Add(targetHeading, 0, 0);

        TableLayoutPanel targetActions = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 1,
            BackColor = Color.Transparent,
            Margin = Padding.Empty
        };
        targetActions.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 108));
        targetActions.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 24));
        targetActions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        _simpleTargetInput = new NumericEntry
        {
            Minimum = 5,
            Maximum = 60,
            Value = 12,
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 10, 4, 10),
            AccessibleName = "简洁模式目标功耗",
            TabIndex = 0
        };
        AppTheme.StyleNumberInput(_simpleTargetInput);
        _simpleTargetInput.Font = new Font("Microsoft YaHei UI", 12F, FontStyle.Bold);
        _simpleTargetInput.ValueChanged += delegate
        {
            if (!_syncingTargets)
            {
                SyncAdvancedTargetsFromSimple();
            }
            UpdatePresetSelection();
            UpdateApplyButtonText();
        };
        targetActions.Controls.Add(_simpleTargetInput, 0, 0);
        Label targetUnit = AppTheme.CreateLabel(
            "W",
            AppTheme.BodyBold,
            AppTheme.TextMuted,
            ContentAlignment.MiddleLeft);
        targetUnit.Dock = DockStyle.Fill;
        targetUnit.Margin = Padding.Empty;
        targetUnit.AutoEllipsis = false;
        targetActions.Controls.Add(targetUnit, 1, 0);
        _simpleApplyButton = new FlatTextButton
        {
            Text = "应用 12 W",
            Dock = DockStyle.Fill,
            Margin = new Padding(10, 10, 0, 10),
            BackColor = AppTheme.Accent,
            ForeColor = Color.White,
            Font = AppTheme.BodyBold,
            Cursor = Cursors.Hand,
            TabStop = true,
            TabIndex = 1,
            AccessibleName = "应用简洁模式功耗"
        };
        _simpleApplyButton.FlatAppearance.BorderSize = 0;
        _simpleApplyButton.FlatAppearance.MouseOverBackColor = AppTheme.AccentHover;
        _simpleApplyButton.FlatAppearance.MouseDownBackColor = AppTheme.AccentHover;
        _simpleApplyButton.Click += async delegate { await ApplySimpleTargetAsync(); };
        targetActions.Controls.Add(_simpleApplyButton, 2, 0);
        target.Controls.Add(targetActions, 0, 1);
        hero.Controls.Add(target, 2, 0);
        return hero;
    }

    private Control BuildSimplePresetStrip()
    {
        TableLayoutPanel presets = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 6,
            RowCount = 1,
            BackColor = Color.Transparent,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        presets.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 52));
        presets.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 8));
        presets.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.333F));
        presets.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.333F));
        presets.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.334F));
        presets.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 84));

        Label presetLabel = AppTheme.CreateLabel(
            "快捷功耗",
            AppTheme.Small,
            AppTheme.TextMuted);
        presetLabel.Dock = DockStyle.Fill;
        presetLabel.Margin = Padding.Empty;
        presetLabel.AutoEllipsis = false;
        presets.Controls.Add(presetLabel, 0, 0);

        for (int index = 0; index < _simplePresetButtons.Length; index++)
        {
            int selectedIndex = index;
            FlatTextButton button = new()
            {
                Text = $"{_presets[index]} W",
                Dock = DockStyle.Fill,
                Margin = new Padding(0, 2, 8, 2),
                BackColor = AppTheme.Surface,
                ForeColor = AppTheme.Text,
                Font = AppTheme.BodyBold,
                Cursor = Cursors.Hand,
                TabStop = true,
                TabIndex = index + 2,
                AccessibleName = $"简洁模式快速预设 {index + 1}"
            };
            button.FlatAppearance.BorderSize = 1;
            button.FlatAppearance.BorderColor = AppTheme.Border;
            button.Click += async delegate { await ApplyPresetAsync(selectedIndex); };
            _simplePresetButtons[index] = button;
            presets.Controls.Add(button, index + 2, 0);
        }

        _simpleEditPresetButton = new FlatTextButton
        {
            Text = "编辑预设",
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 2, 0, 2),
            BackColor = AppTheme.Surface,
            ForeColor = AppTheme.Text,
            Font = AppTheme.SmallBold,
            Cursor = Cursors.Hand,
            TabStop = true,
            TabIndex = 5,
            AccessibleName = "编辑简洁模式快速预设"
        };
        _simpleEditPresetButton.FlatAppearance.BorderSize = 1;
        _simpleEditPresetButton.FlatAppearance.BorderColor = AppTheme.Border;
        _simpleEditPresetButton.FlatAppearance.MouseOverBackColor = AppTheme.SurfaceMuted;
        _simpleEditPresetButton.FlatAppearance.MouseDownBackColor = AppTheme.Border;
        _simpleEditPresetButton.Click += delegate { ShowPresetEditor(); };
        presets.Controls.Add(_simpleEditPresetButton, 5, 0);
        return presets;
    }

    private Control BuildSimpleTelemetryMatrix()
    {
        TableLayoutPanel matrix = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 4,
            RowCount = 1,
            BackColor = AppTheme.SurfaceMuted,
            CellBorderStyle = TableLayoutPanelCellBorderStyle.Single,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        for (int index = 0; index < 4; index++)
        {
            matrix.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
        }

        string[] titles = ["STAPM", "PPT Fast", "PPT Slow", "CPU 温度"];
        for (int index = 0; index < titles.Length; index++)
        {
            SimpleMetricTile tile = new(titles[index]);
            matrix.Controls.Add(tile, index, 0);
            _simpleMetricTiles[index] = tile;
        }

        _simpleStapmValue = _simpleMetricTiles[0].ValueLabel;
        _simpleStapmLimitValue = _simpleMetricTiles[0].LimitLabel;
        _simpleFastValue = _simpleMetricTiles[1].ValueLabel;
        _simpleFastLimitValue = _simpleMetricTiles[1].LimitLabel;
        _simpleSlowValue = _simpleMetricTiles[2].ValueLabel;
        _simpleSlowLimitValue = _simpleMetricTiles[2].LimitLabel;
        _simpleTemperatureValue = _simpleMetricTiles[3].ValueLabel;
        _simpleTemperatureLimitValue = _simpleMetricTiles[3].LimitLabel;
        return matrix;
    }

    private Control BuildSimpleStatusBar()
    {
        _simpleStatusBar = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 4,
            RowCount = 1,
            BackColor = AppTheme.SurfaceMuted,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        _simpleStatusBar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 92));
        _simpleStatusBar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 8));
        _simpleStatusBar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        _simpleStatusBar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 58));

        _simpleWriteStateLabel = AppTheme.CreateLabel(
            _writeControlsEnabled ? "写入模式" : "只读模式",
            AppTheme.SmallBold,
            _writeControlsEnabled ? AppTheme.Accent : AppTheme.TextMuted,
            ContentAlignment.MiddleCenter);
        _simpleWriteStateLabel.Dock = DockStyle.Fill;
        _simpleWriteStateLabel.Margin = new Padding(0, 6, 0, 6);
        _simpleWriteStateLabel.BackColor = _writeControlsEnabled
            ? AppTheme.AccentSoft
            : AppTheme.Border;
        _simpleWriteStateLabel.AutoEllipsis = false;
        _simpleStatusBar.Controls.Add(_simpleWriteStateLabel, 0, 0);

        _simpleStatusLabel = AppTheme.CreateLabel(
            "正在连接 worker...",
            AppTheme.Small,
            AppTheme.TextMuted,
            ContentAlignment.MiddleLeft);
        _simpleStatusLabel.Dock = DockStyle.Fill;
        _simpleStatusLabel.Margin = Padding.Empty;
        _simpleStatusLabel.Padding = new Padding(2, 0, 6, 0);
        _simpleStatusLabel.BackColor = Color.Transparent;
        _simpleStatusLabel.AutoEllipsis = false;
        _simpleStatusBar.Controls.Add(_simpleStatusLabel, 2, 0);

        FlatTextButton details = new()
        {
            Text = "详情",
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 4, 0, 4),
            BackColor = Color.Transparent,
            ForeColor = AppTheme.TextMuted,
            Font = AppTheme.SmallBold,
            Cursor = Cursors.Hand,
            TabStop = true,
            TabIndex = 6,
            AccessibleName = "打开高级模式查看详情"
        };
        details.FlatAppearance.BorderSize = 0;
        details.FlatAppearance.MouseOverBackColor = AppTheme.Surface;
        details.FlatAppearance.MouseDownBackColor = AppTheme.Border;
        details.Click += delegate { SwitchDisplayMode(UiMode.Advanced); };
        _simpleStatusBar.Controls.Add(details, 3, 0);
        return _simpleStatusBar;
    }

    [Obsolete("Legacy simple-mode sketch. Modify BuildSimpleWorkspace instead.")]
    private Control BuildLegacySimpleContentOne()
    {
        TableLayoutPanel layout = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 6,
            BackColor = Color.Transparent
        };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 56));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 16));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 60));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 8));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));

        TableLayoutPanel target = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            BackColor = Color.Transparent
        };
        target.RowStyles.Add(new RowStyle(SizeType.Absolute, 18));
        target.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));

        TableLayoutPanel targetHeading = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            BackColor = Color.Transparent
        };
        targetHeading.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        targetHeading.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        Label targetLabel = AppTheme.CreateLabel(
            "目标功耗",
            AppTheme.BodyBold,
            AppTheme.Text);
        targetLabel.Dock = DockStyle.Fill;
        targetHeading.Controls.Add(targetLabel, 0, 0);
        _simpleRangeLabel = AppTheme.CreateLabel(
            "范围 5-60 W",
            AppTheme.Small,
            AppTheme.TextMuted,
            ContentAlignment.MiddleRight);
        _simpleRangeLabel.Dock = DockStyle.Fill;
        targetHeading.Controls.Add(_simpleRangeLabel, 1, 0);
        target.Controls.Add(targetHeading, 0, 0);

        TableLayoutPanel targetActions = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 4,
            RowCount = 1,
            BackColor = Color.Transparent
        };
        targetActions.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
        targetActions.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 28));
        targetActions.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 140));
        targetActions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        _simpleTargetInput = new NumericEntry
        {
            Minimum = 5,
            Maximum = 60,
            Value = 12,
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 2, 4, 2),
            AccessibleName = "简洁模式目标功耗"
        };
        AppTheme.StyleNumberInput(_simpleTargetInput);
        _simpleTargetInput.Font = new Font("Microsoft YaHei UI", 14F, FontStyle.Bold);
        _simpleTargetInput.ValueChanged += delegate
        {
            if (!_syncingTargets)
            {
                SyncAdvancedTargetsFromSimple();
            }
            UpdatePresetSelection();
            UpdateApplyButtonText();
        };
        targetActions.Controls.Add(_simpleTargetInput, 0, 0);

        Label targetUnit = AppTheme.CreateLabel(
            "W",
            AppTheme.BodyBold,
            AppTheme.TextMuted);
        targetUnit.Dock = DockStyle.Fill;
        targetActions.Controls.Add(targetUnit, 1, 0);

        _simpleApplyButton = AppTheme.CreateButton(
            "应用 12 W",
            primary: true,
            width: 140,
            height: 38);
        _simpleApplyButton.Dock = DockStyle.Fill;
        _simpleApplyButton.Margin = new Padding(12, 0, 0, 0);
        _simpleApplyButton.AccessibleName = "应用简洁模式功耗";
        _simpleApplyButton.Click += async delegate { await ApplySimpleTargetAsync(); };
        targetActions.Controls.Add(_simpleApplyButton, 2, 0);
        target.Controls.Add(targetActions, 0, 1);
        layout.Controls.Add(target, 0, 0);

        TableLayoutPanel presets = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            BackColor = Color.Transparent
        };
        presets.RowStyles.Add(new RowStyle(SizeType.Absolute, 18));
        presets.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));

        Label presetLabel = AppTheme.CreateLabel(
            "快速预设",
            AppTheme.Small,
            AppTheme.TextMuted);
        presetLabel.Dock = DockStyle.Fill;
        presets.Controls.Add(presetLabel, 0, 0);

        TableLayoutPanel presetButtons = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 4,
            RowCount = 1,
            BackColor = Color.Transparent
        };
        for (int index = 0; index < 4; index++)
        {
            presetButtons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
        }
        for (int index = 0; index < _simplePresetButtons.Length; index++)
        {
            int selectedIndex = index;
            Button button = AppTheme.CreateButton(
                $"{_presets[index]} W",
                width: 118,
                height: 38);
            button.Dock = DockStyle.Fill;
            button.Margin = new Padding(0, 0, 8, 0);
            button.Font = new Font("Microsoft YaHei UI", 11F, FontStyle.Bold);
            button.AccessibleName = $"简洁模式快速预设 {index + 1}";
            button.Click += async delegate
            {
                await ApplyPresetAsync(selectedIndex);
            };
            _simplePresetButtons[index] = button;
            presetButtons.Controls.Add(button, index, 0);
        }
        _simpleEditPresetButton = AppTheme.CreateButton(
            "编辑预设",
            width: 128,
            height: 38);
        _simpleEditPresetButton.Dock = DockStyle.Fill;
        _simpleEditPresetButton.Margin = Padding.Empty;
        _simpleEditPresetButton.AccessibleName = "编辑简洁模式快速预设";
        _simpleEditPresetButton.Click += delegate { ShowPresetEditor(); };
        presetButtons.Controls.Add(_simpleEditPresetButton, 3, 0);
        presets.Controls.Add(presetButtons, 0, 1);
        layout.Controls.Add(presets, 0, 2);

        Panel dividerHost = new()
        {
            Dock = DockStyle.Fill,
            BackColor = Color.Transparent
        };
        dividerHost.Controls.Add(new Panel
        {
            Dock = DockStyle.Bottom,
            Height = 1,
            BackColor = AppTheme.Border
        });
        layout.Controls.Add(dividerHost, 0, 3);

        TableLayoutPanel stats = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            BackColor = Color.Transparent
        };
        stats.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 240));
        stats.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        TableLayoutPanel livePanel = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 4,
            BackColor = Color.Transparent
        };
        livePanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 20));
        livePanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 56));
        livePanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
        livePanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 12));

        Panel liveHeading = new() { Dock = DockStyle.Fill, BackColor = Color.Transparent };
        Label liveCaption = AppTheme.CreateLabel(
            "STAPM 实时功耗",
            AppTheme.Small,
            AppTheme.TextMuted);
        liveCaption.Location = Point.Empty;
        liveCaption.Size = new Size(128, 20);
        liveHeading.Controls.Add(liveCaption);

        _simplePowerLineBadge = AppTheme.CreateLabel(
            "电源",
            AppTheme.SmallBold,
            AppTheme.Text,
            ContentAlignment.MiddleCenter);
        _simplePowerLineBadge.Location = new Point(132, 0);
        _simplePowerLineBadge.Size = new Size(100, 20);
        _simplePowerLineBadge.BackColor = AppTheme.SurfaceMuted;
        liveHeading.Controls.Add(_simplePowerLineBadge);
        _simpleWriteStateLabel = AppTheme.CreateLabel(
            _writeControlsEnabled ? "写入已解锁" : "只读模式",
            AppTheme.Small,
            AppTheme.TextMuted,
            ContentAlignment.MiddleRight);
        _simpleWriteStateLabel.Visible = false;
        liveHeading.Controls.Add(_simpleWriteStateLabel);
        livePanel.Controls.Add(liveHeading, 0, 0);

        Panel liveValue = new() { Dock = DockStyle.Fill, BackColor = Color.Transparent };
        _simpleCurrentPower = AppTheme.CreateLabel("--", AppTheme.Display, AppTheme.Accent);
        _simpleCurrentPower.Location = Point.Empty;
        _simpleCurrentPower.Size = new Size(170, 54);
        _simpleCurrentPower.Font = new Font("Segoe UI Variable Display", 28F, FontStyle.Bold);
        liveValue.Controls.Add(_simpleCurrentPower);
        Label watts = AppTheme.CreateLabel("W", AppTheme.BodyBold, AppTheme.TextMuted);
        watts.Location = new Point(170, 27);
        watts.Size = new Size(24, 20);
        liveValue.Controls.Add(watts);
        livePanel.Controls.Add(liveValue, 0, 1);

        _simpleLimitSummary = AppTheme.CreateLabel(
            "STAPM 上限 -- W",
            AppTheme.Small,
            AppTheme.TextMuted);
        _simpleLimitSummary.Dock = DockStyle.Fill;
        livePanel.Controls.Add(_simpleLimitSummary, 0, 2);

        _simplePowerBar = new PowerUsageBar
        {
            Dock = DockStyle.Fill,
            Height = 9,
            Margin = Padding.Empty
        };
        livePanel.Controls.Add(_simplePowerBar, 0, 3);
        stats.Controls.Add(livePanel, 0, 0);

        TableLayoutPanel metrics = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 5,
            BackColor = Color.Transparent
        };
        metrics.RowStyles.Add(new RowStyle(SizeType.Absolute, 20));
        metrics.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 92));
        metrics.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        for (int index = 0; index < 4; index++)
        {
            metrics.RowStyles.Add(new RowStyle(SizeType.Percent, 25));
        }
        Label metricHeading = AppTheme.CreateLabel(
            "实时 / 上限",
            AppTheme.Small,
            AppTheme.TextMuted,
            ContentAlignment.MiddleRight);
        metricHeading.Dock = DockStyle.Fill;
        metrics.SetColumnSpan(metricHeading, 2);
        metrics.Controls.Add(metricHeading, 0, 0);

        string[] metricNames =
        [
            "STAPM",
            "PPT Fast",
            "PPT Slow",
            "CPU 温度"
        ];
        Label[] metricValues =
        [
            _simpleStapmValue,
            _simpleFastValue,
            _simpleSlowValue,
            _simpleTemperatureValue
        ];
        for (int index = 0; index < metricNames.Length; index++)
        {
            Label caption = AppTheme.CreateLabel(
                metricNames[index],
                AppTheme.Small,
                AppTheme.TextMuted);
            caption.Dock = DockStyle.Fill;
            caption.Margin = Padding.Empty;
            metrics.Controls.Add(caption, 0, index + 1);

            Label value = AppTheme.CreateLabel(
                "--",
                AppTheme.BodyBold,
                AppTheme.Text);
            value.Dock = DockStyle.Fill;
            value.Margin = Padding.Empty;
            value.AutoEllipsis = true;
            metrics.Controls.Add(value, 1, index + 1);
            metricValues[index] = value;
        }
        _simpleStapmValue = metricValues[0];
        _simpleFastValue = metricValues[1];
        _simpleSlowValue = metricValues[2];
        _simpleTemperatureValue = metricValues[3];
        stats.Controls.Add(metrics, 1, 0);
        layout.Controls.Add(stats, 0, 4);

        _simpleStatusLabel = AppTheme.CreateLabel(
            "正在连接 worker...",
            AppTheme.Small,
            AppTheme.TextMuted);
        _simpleStatusLabel.Dock = DockStyle.Fill;
        _simpleStatusLabel.Padding = new Padding(8, 2, 8, 2);
        _simpleStatusLabel.BackColor = AppTheme.SurfaceMuted;
        _simpleStatusLabel.AutoEllipsis = true;
        layout.Controls.Add(_simpleStatusLabel, 0, 5);

        return layout;
    }

    [Obsolete("Legacy compact-mode layout. Modify BuildSimpleWorkspace instead.")]
    private Control BuildLegacySimpleContentTwo()
    {
        TableLayoutPanel page = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            BackColor = Color.Transparent,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        page.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 32));

        TableLayoutPanel shell = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 1,
            BackColor = Color.Transparent,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 132));
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 14));
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        shell.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        TableLayoutPanel quickPanel = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 9,
            BackColor = AppTheme.SurfaceMuted,
            Margin = Padding.Empty,
            Padding = new Padding(12)
        };
        quickPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        quickPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        quickPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 10));
        quickPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        quickPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 10));
        quickPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        quickPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 10));
        quickPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
        quickPanel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        Label quickLabel = AppTheme.CreateLabel(
            "快捷功耗",
            AppTheme.BodyBold,
            AppTheme.Text);
        quickLabel.Dock = DockStyle.Fill;
        quickLabel.Margin = Padding.Empty;
        quickPanel.Controls.Add(quickLabel, 0, 0);

        for (int index = 0; index < _simplePresetButtons.Length; index++)
        {
            int selectedIndex = index;
            Button button = AppTheme.CreateButton(
                $"{_presets[index]} W",
                width: 108,
                height: 48);
            button.Dock = DockStyle.Fill;
            button.Margin = Padding.Empty;
            button.Font = new Font("Microsoft YaHei UI", 11F, FontStyle.Bold);
            button.AccessibleName = $"简洁模式快速预设 {index + 1}";
            button.Click += async delegate { await ApplyPresetAsync(selectedIndex); };
            _simplePresetButtons[index] = button;
            quickPanel.Controls.Add(button, 0, 1 + index * 2);
        }

        _simpleEditPresetButton = AppTheme.CreateButton(
            "编辑预设",
            width: 108,
            height: 42);
        _simpleEditPresetButton.Dock = DockStyle.Fill;
        _simpleEditPresetButton.Margin = Padding.Empty;
        _simpleEditPresetButton.Font = AppTheme.BodyBold;
        _simpleEditPresetButton.AccessibleName = "编辑简洁模式快速预设";
        _simpleEditPresetButton.Click += delegate { ShowPresetEditor(); };
        quickPanel.Controls.Add(_simpleEditPresetButton, 0, 7);
        shell.Controls.Add(quickPanel, 0, 0);

        TableLayoutPanel main = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            BackColor = Color.Transparent,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        main.RowStyles.Add(new RowStyle(SizeType.Absolute, 68));
        main.RowStyles.Add(new RowStyle(SizeType.Absolute, 10));
        main.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        TableLayoutPanel live = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            BackColor = Color.Transparent
        };
        live.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
        live.RowStyles.Add(new RowStyle(SizeType.Absolute, 58));
        live.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));

        TableLayoutPanel liveHeading = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            BackColor = Color.Transparent
        };
        liveHeading.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        liveHeading.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 52));
        Label liveCaption = AppTheme.CreateLabel(
            "STAPM 实时",
            AppTheme.Small,
            AppTheme.TextMuted);
        liveCaption.Dock = DockStyle.Fill;
        liveCaption.Margin = Padding.Empty;
        liveHeading.Controls.Add(liveCaption, 0, 0);

        _simplePowerLineBadge = AppTheme.CreateLabel(
            "--",
            AppTheme.SmallBold,
            AppTheme.Text,
            ContentAlignment.MiddleCenter);
        _simplePowerLineBadge.Dock = DockStyle.Fill;
        _simplePowerLineBadge.Margin = Padding.Empty;
        _simplePowerLineBadge.BackColor = AppTheme.SurfaceMuted;
        liveHeading.Controls.Add(_simplePowerLineBadge, 1, 0);
        live.Controls.Add(liveHeading, 0, 0);

        TableLayoutPanel liveValues = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            BackColor = Color.Transparent
        };
        liveValues.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        liveValues.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 26));
        _simpleCurrentPower = AppTheme.CreateLabel("--", AppTheme.Display, AppTheme.Accent);
        _simpleCurrentPower.Dock = DockStyle.Fill;
        _simpleCurrentPower.Font = new Font("Segoe UI Variable Display", 28F, FontStyle.Bold);
        _simpleCurrentPower.TextAlign = ContentAlignment.MiddleLeft;
        _simpleCurrentPower.Margin = Padding.Empty;
        _simpleCurrentPower.AutoEllipsis = false;
        liveValues.Controls.Add(_simpleCurrentPower, 0, 0);
        Label watts = AppTheme.CreateLabel(
            "W",
            AppTheme.BodyBold,
            AppTheme.TextMuted,
            ContentAlignment.BottomLeft);
        watts.Dock = DockStyle.Fill;
        watts.Margin = Padding.Empty;
        watts.Padding = new Padding(0, 0, 0, 8);
        liveValues.Controls.Add(watts, 1, 0);
        live.Controls.Add(liveValues, 0, 1);

        _simpleWriteStateLabel = AppTheme.CreateLabel(
            _writeControlsEnabled ? "写入已解锁" : "只读模式",
            AppTheme.Small,
            AppTheme.TextMuted);
        _simpleWriteStateLabel.Visible = false;
        _simpleLimitSummary = AppTheme.CreateLabel(
            "STAPM 上限 -- W · 目标 12 W",
            AppTheme.Small,
            AppTheme.TextMuted);
        _simpleLimitSummary.Dock = DockStyle.Fill;
        _simpleLimitSummary.Margin = Padding.Empty;
        _simpleLimitSummary.AutoEllipsis = false;
        live.Controls.Add(_simpleLimitSummary, 0, 2);

        TableLayoutPanel target = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 4,
            RowCount = 1,
            BackColor = Color.Transparent
        };
        target.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        target.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 84));
        target.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 116));
        target.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 26));
        target.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        Label targetLabel = AppTheme.CreateLabel(
            "目标功耗",
            AppTheme.BodyBold,
            AppTheme.Text);
        targetLabel.Dock = DockStyle.Fill;
        targetLabel.Margin = Padding.Empty;
        targetLabel.AutoEllipsis = false;
        target.Controls.Add(targetLabel, 0, 0);
        _simpleRangeLabel = AppTheme.CreateLabel(
            "5-60 W",
            AppTheme.Small,
            AppTheme.TextMuted,
            ContentAlignment.MiddleRight);
        _simpleRangeLabel.Visible = false;

        _simpleTargetInput = new NumericEntry
        {
            Minimum = 5,
            Maximum = 60,
            Value = 12,
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 14, 4, 14),
            AccessibleName = "简洁模式目标功耗"
        };
        AppTheme.StyleNumberInput(_simpleTargetInput);
        _simpleTargetInput.Font = new Font("Microsoft YaHei UI", 13F, FontStyle.Bold);
        _simpleTargetInput.ValueChanged += delegate
        {
            if (!_syncingTargets)
            {
                SyncAdvancedTargetsFromSimple();
            }
            UpdatePresetSelection();
            UpdateApplyButtonText();
        };
        target.Controls.Add(_simpleTargetInput, 1, 0);
        Label targetUnit = AppTheme.CreateLabel(
            "W",
            AppTheme.BodyBold,
            AppTheme.TextMuted,
            ContentAlignment.MiddleLeft);
        targetUnit.Dock = DockStyle.Fill;
        targetUnit.Margin = Padding.Empty;
        target.Controls.Add(targetUnit, 2, 0);
        _simpleApplyButton = new FlatTextButton
        {
            Text = "应用 12 W",
            Width = 150,
            Height = 40,
            BackColor = AppTheme.Accent,
            ForeColor = Color.White,
            Font = AppTheme.BodyBold,
            Cursor = Cursors.Hand,
            TabStop = true
        };
        _simpleApplyButton.FlatAppearance.BorderSize = 0;
        _simpleApplyButton.Dock = DockStyle.Fill;
        _simpleApplyButton.Margin = new Padding(12, 14, 0, 14);
        _simpleApplyButton.AccessibleName = "应用简洁模式功耗";
        _simpleApplyButton.Click += async delegate { await ApplySimpleTargetAsync(); };
        target.Controls.Add(_simpleApplyButton, 3, 0);
        main.Controls.Add(target, 0, 0);

        TableLayoutPanel stats = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 1,
            BackColor = Color.Transparent,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        stats.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 178));
        stats.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 14));
        stats.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        stats.Controls.Add(live, 0, 0);

        TableLayoutPanel metrics = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 5,
            BackColor = AppTheme.SurfaceMuted,
            Margin = Padding.Empty,
            Padding = new Padding(10, 8, 10, 8)
        };
        metrics.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 86));
        metrics.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        metrics.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
        for (int index = 0; index < 4; index++)
        {
            metrics.RowStyles.Add(new RowStyle(SizeType.Percent, 25));
        }

        Label metricHeading = AppTheme.CreateLabel(
            "实时 / 上限",
            AppTheme.Small,
            AppTheme.TextMuted,
            ContentAlignment.MiddleRight);
        metricHeading.Dock = DockStyle.Fill;
        metricHeading.Margin = Padding.Empty;
        metrics.SetColumnSpan(metricHeading, 2);
        metrics.Controls.Add(metricHeading, 0, 0);

        string[] metricNames = ["STAPM", "PPT Fast", "PPT Slow", "CPU 温度"];
        Label[] metricValues =
        [
            _simpleStapmValue,
            _simpleFastValue,
            _simpleSlowValue,
            _simpleTemperatureValue
        ];
        for (int index = 0; index < metricNames.Length; index++)
        {
            Label caption = AppTheme.CreateLabel(
                metricNames[index],
                AppTheme.Body,
                AppTheme.TextMuted);
            caption.Dock = DockStyle.Fill;
            caption.Margin = Padding.Empty;
            metrics.Controls.Add(caption, 0, index + 1);

            Label value = AppTheme.CreateLabel(
                "--",
                AppTheme.BodyBold,
                AppTheme.Text);
            value.Dock = DockStyle.Fill;
            value.Margin = Padding.Empty;
            value.AutoEllipsis = false;
            value.TextAlign = ContentAlignment.MiddleRight;
            metrics.Controls.Add(value, 1, index + 1);
            metricValues[index] = value;
        }
        _simpleStapmValue = metricValues[0];
        _simpleFastValue = metricValues[1];
        _simpleSlowValue = metricValues[2];
        _simpleTemperatureValue = metricValues[3];
        stats.Controls.Add(metrics, 2, 0);
        main.Controls.Add(stats, 0, 2);

        _simpleStatusLabel = AppTheme.CreateLabel(
            "正在连接 worker...",
            AppTheme.Body,
            AppTheme.TextMuted,
            ContentAlignment.MiddleLeft);
        _simpleStatusLabel.Dock = DockStyle.Fill;
        _simpleStatusLabel.Margin = Padding.Empty;
        _simpleStatusLabel.Padding = new Padding(146, 0, 8, 0);
        _simpleStatusLabel.BackColor = AppTheme.SurfaceMuted;
        _simpleStatusLabel.AutoEllipsis = false;
        shell.Controls.Add(main, 2, 0);
        page.Controls.Add(shell, 0, 0);
        page.Controls.Add(_simpleStatusLabel, 0, 1);
        UpdateApplyButtonText();

        return page;
    }

    private Control BuildSnapshotContent()
    {
        TableLayoutPanel layout = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 5,
            BackColor = Color.Transparent
        };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 92));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 50));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 54));

        Label heading = AppTheme.CreateLabel(
            "当前状态",
            AppTheme.Heading,
            AppTheme.Text);
        layout.Controls.Add(heading, 0, 0);

        Panel powerPanel = new() { Dock = DockStyle.Fill, BackColor = Color.Transparent };
        _currentPower = AppTheme.CreateLabel("--", AppTheme.Display, AppTheme.Accent);
        _currentPower.Location = new Point(0, 0);
        _currentPower.Size = new Size(150, 70);
        _currentPower.Font = new Font("Segoe UI Variable Display", 31F, FontStyle.Bold);
        powerPanel.Controls.Add(_currentPower);
        Label watts = AppTheme.CreateLabel("W", AppTheme.BodyBold, AppTheme.TextMuted);
        watts.Location = new Point(150, 39);
        watts.Size = new Size(28, 24);
        powerPanel.Controls.Add(watts);
        Label realCaption = AppTheme.CreateLabel("STAPM 实时", AppTheme.Small, AppTheme.TextMuted);
        realCaption.Location = new Point(196, 13);
        realCaption.Size = new Size(120, 20);
        powerPanel.Controls.Add(realCaption);
        layout.Controls.Add(powerPanel, 0, 1);

        Panel linePanel = new() { Dock = DockStyle.Fill, BackColor = Color.Transparent };
        _powerLineBadge = AppTheme.CreateLabel(
            "电源 --",
            AppTheme.SmallBold,
            AppTheme.Text,
            ContentAlignment.MiddleCenter);
        _powerLineBadge.Location = new Point(0, 2);
        _powerLineBadge.Size = new Size(104, 28);
        _powerLineBadge.BackColor = AppTheme.SurfaceMuted;
        linePanel.Controls.Add(_powerLineBadge);

        _powerBar = new PowerUsageBar
        {
            Location = new Point(120, 10),
            Width = 320,
            Height = 12,
            Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right
        };
        linePanel.Controls.Add(_powerBar);
        linePanel.Resize += delegate
        {
            _powerBar.Width = Math.Max(40, linePanel.ClientSize.Width - 120);
        };
        layout.Controls.Add(linePanel, 0, 2);

        TableLayoutPanel metrics = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 4,
            BackColor = Color.Transparent,
            Padding = new Padding(0, 10, 0, 6)
        };
        metrics.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        metrics.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        for (int index = 0; index < 4; index++)
        {
            metrics.RowStyles.Add(new RowStyle(SizeType.Percent, 25));
        }

        metrics.Controls.Add(CreateMetric("STAPM 实际 / 动态上限", out _stapmValue), 0, 0);
        metrics.Controls.Add(CreateMetric("PPT Fast 实际 / 上限", out _fastValue), 1, 0);
        metrics.Controls.Add(CreateMetric("PPT Slow 实际 / 上限", out _slowValue), 0, 1);
        metrics.Controls.Add(CreateMetric("CPU 温度 实际 / 上限", out _temperatureValue), 1, 1);
        metrics.Controls.Add(CreateMetric("匹配配置", out _profileValue), 0, 2);
        metrics.Controls.Add(CreateMetric("允许范围", out _rangeValue), 1, 2);

        Label divider = new()
        {
            Dock = DockStyle.Bottom,
            Height = 1,
            BackColor = AppTheme.Border
        };
        metrics.SetColumnSpan(divider, 2);
        metrics.Controls.Add(divider, 0, 3);
        layout.Controls.Add(metrics, 0, 3);

        _statusLabel = AppTheme.CreateLabel(
            "正在连接 worker...",
            AppTheme.Small,
            AppTheme.TextMuted);
        _statusLabel.Dock = DockStyle.Fill;
        _statusLabel.Padding = new Padding(10, 4, 10, 4);
        _statusLabel.BackColor = AppTheme.SurfaceMuted;
        _statusLabel.AutoEllipsis = true;
        layout.Controls.Add(_statusLabel, 0, 4);

        return layout;
    }

    private Control BuildControlContent()
    {
        TableLayoutPanel layout = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 6,
            BackColor = Color.Transparent
        };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 150));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 64));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 46));

        Label heading = AppTheme.CreateLabel(
            "功耗目标",
            AppTheme.Heading,
            AppTheme.Text);
        layout.Controls.Add(heading, 0, 0);

        _writeStateLabel = AppTheme.CreateLabel(
            _writeControlsEnabled ? "写入已解锁" : "只读模式",
            AppTheme.Small,
            AppTheme.TextMuted);
        layout.Controls.Add(_writeStateLabel, 0, 1);

        TableLayoutPanel inputs = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 3,
            BackColor = Color.Transparent,
            Padding = new Padding(0, 2, 0, 2)
        };
        inputs.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 38));
        inputs.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 48));
        inputs.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 14));
        for (int index = 0; index < 3; index++)
        {
            inputs.RowStyles.Add(new RowStyle(SizeType.Percent, 33.333F));
        }

        string[] names = ["STAPM", "PPT Fast", "PPT Slow"];
        for (int index = 0; index < _limitInputs.Length; index++)
        {
            Label label = AppTheme.CreateLabel(names[index], AppTheme.Body, AppTheme.TextMuted);
            label.Dock = DockStyle.Fill;
            inputs.Controls.Add(label, 0, index);

            NumericEntry input = new()
            {
                Minimum = 5,
                Maximum = 60,
                Value = 12,
                Dock = DockStyle.Fill,
                Margin = new Padding(0, 5, 8, 5),
                AccessibleName = names[index] + " 目标功耗"
            };
            AppTheme.StyleNumberInput(input);
            input.ValueChanged += delegate
            {
                if (!_syncingTargets)
                {
                    SyncSimpleTargetFromAdvanced();
                }
                UpdatePresetSelection();
                UpdateApplyButtonText();
            };
            inputs.Controls.Add(input, 1, index);
            _limitInputs[index] = input;

            Label unit = AppTheme.CreateLabel("W", AppTheme.BodyBold, AppTheme.TextMuted);
            unit.Dock = DockStyle.Fill;
            inputs.Controls.Add(unit, 2, index);
        }
        layout.Controls.Add(inputs, 0, 2);

        FlowLayoutPanel presets = new()
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.Transparent,
            Padding = new Padding(0, 8, 0, 6)
        };
        for (int index = 0; index < _presetButtons.Length; index++)
        {
            int selectedIndex = index;
            Button button = AppTheme.CreateButton(
                $"{_presets[index]} W",
                width: 66,
                height: 38);
            button.Margin = new Padding(0, 0, 5, 0);
            button.AccessibleName = $"快速预设 {index + 1}";
            button.Click += async delegate
            {
                await ApplyPresetAsync(selectedIndex);
            };
            _presetButtons[index] = button;
            presets.Controls.Add(button);
        }

        _editPresetButton = AppTheme.CreateButton(
            "编辑",
            width: 70,
            height: 38);
        _editPresetButton.Margin = Padding.Empty;
        _editPresetButton.Click += delegate { ShowPresetEditor(); };
        presets.Controls.Add(_editPresetButton);
        layout.Controls.Add(presets, 0, 3);

        layout.Controls.Add(BuildPolicyPanel(), 0, 4);

        FlowLayoutPanel actions = new()
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            WrapContents = false,
            BackColor = Color.Transparent,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };

        _applyButton = AppTheme.CreateButton(
            "应用三项限制",
            primary: true,
            width: 220,
            height: 40);
        _applyButton.Margin = new Padding(8, 3, 0, 3);
        _applyButton.Click += async delegate { await ApplyCurrentTargetAsync(); };
        actions.Controls.Add(_applyButton);

        _diagnosticsButton = AppTheme.CreateButton(
            "导出诊断",
            width: 120,
            height: 40);
        _diagnosticsButton.Margin = new Padding(0, 3, 0, 3);
        _diagnosticsButton.AccessibleName = "导出诊断";
        _diagnosticsButton.Click += async delegate { await ExportDiagnosticsAsync(); };
        actions.Controls.Add(_diagnosticsButton);
        layout.Controls.Add(actions, 0, 5);
        SetApplyEnabled(false);

        _inputsInitialized = false;
        UpdatePresetSelection();
        return layout;
    }

    private Control BuildFooter()
    {
        Panel footer = new()
        {
            Dock = DockStyle.Fill,
            BackColor = Color.FromArgb(235, 239, 235),
            Padding = new Padding(26, 4, 26, 4)
        };

        _updatedLabel = AppTheme.CreateLabel(
            "尚未读取",
            AppTheme.Small,
            AppTheme.TextMuted);
        _updatedLabel.Location = new Point(26, 5);
        _updatedLabel.Size = new Size(440, 24);
        footer.Controls.Add(_updatedLabel);

        string productVersion = Application.ProductVersion;
        int buildMetadataIndex = productVersion.IndexOf('+', StringComparison.Ordinal);
        if (buildMetadataIndex >= 0)
        {
            productVersion = productVersion[..buildMetadataIndex];
        }
        Label version = AppTheme.CreateLabel(
            $"v{productVersion} · 协议 v{WorkerProtocol.CurrentVersion}",
            AppTheme.Small,
            AppTheme.TextMuted,
            ContentAlignment.MiddleRight);
        version.Size = new Size(250, 24);
        version.Location = new Point(Math.Max(26, footer.Width - 276), 5);
        version.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        footer.Controls.Add(version);
        footer.Resize += delegate
        {
            version.Location = new Point(
                Math.Max(26, footer.ClientSize.Width - 276),
                5);
        };
        return footer;
    }

    private Control BuildPolicyPanel()
    {
        Panel panel = new()
        {
            Dock = DockStyle.Fill,
            BackColor = AppTheme.SurfaceMuted,
            Margin = new Padding(0, 4, 0, 4),
            Padding = new Padding(10, 5, 10, 5)
        };

        TableLayoutPanel layout = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            BackColor = Color.Transparent
        };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        panel.Controls.Add(layout);

        Panel headingRow = new() { Dock = DockStyle.Fill, BackColor = Color.Transparent };
        Label heading = AppTheme.CreateLabel(
            "自动电源策略",
            AppTheme.SmallBold,
            AppTheme.Text);
        heading.Location = Point.Empty;
        heading.Size = new Size(120, 24);
        headingRow.Controls.Add(heading);

        _autoPolicyCheckBox = new CheckBox
        {
            Text = "启用",
            AutoSize = true,
            Font = AppTheme.Small,
            ForeColor = AppTheme.TextMuted,
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            Location = new Point(Math.Max(120, headingRow.Width - 58), 1)
        };
        headingRow.Resize += delegate
        {
            _autoPolicyCheckBox.Location = new Point(
                Math.Max(120, headingRow.ClientSize.Width - 58),
                1);
        };
        headingRow.Controls.Add(_autoPolicyCheckBox);
        layout.Controls.Add(headingRow, 0, 0);

        TableLayoutPanel values = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 2,
            BackColor = Color.Transparent
        };
        values.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 44));
        values.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 78));
        values.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        values.RowStyles.Add(new RowStyle(SizeType.Percent, 50));
        values.RowStyles.Add(new RowStyle(SizeType.Percent, 50));

        Label batteryLabel = AppTheme.CreateLabel(
            "电池",
            AppTheme.Small,
            AppTheme.TextMuted);
        batteryLabel.Dock = DockStyle.Fill;
        values.Controls.Add(batteryLabel, 0, 0);
        _batteryPolicyInput = CreatePolicyInput();
        _batteryPolicyInput.Dock = DockStyle.Fill;
        values.Controls.Add(_batteryPolicyInput, 1, 0);
        Label batteryUnit = AppTheme.CreateLabel(
            "W",
            AppTheme.Small,
            AppTheme.TextMuted);
        batteryUnit.Dock = DockStyle.Fill;
        values.Controls.Add(batteryUnit, 2, 0);

        Label acLabel = AppTheme.CreateLabel(
            "电源",
            AppTheme.Small,
            AppTheme.TextMuted);
        acLabel.Dock = DockStyle.Fill;
        values.Controls.Add(acLabel, 0, 1);
        _acPolicyInput = CreatePolicyInput();
        _acPolicyInput.Dock = DockStyle.Fill;
        values.Controls.Add(_acPolicyInput, 1, 1);
        Label acUnit = AppTheme.CreateLabel(
            "W",
            AppTheme.Small,
            AppTheme.TextMuted);
        acUnit.Dock = DockStyle.Fill;
        values.Controls.Add(acUnit, 2, 1);
        layout.Controls.Add(values, 0, 1);

        Panel actionRow = new() { Dock = DockStyle.Fill, BackColor = Color.Transparent };
        _savePolicyButton = AppTheme.CreateButton("保存策略", width: 100, height: 30);
        _savePolicyButton.Location = Point.Empty;
        _savePolicyButton.Click += async delegate { await SavePowerPolicyAsync(); };
        actionRow.Controls.Add(_savePolicyButton);

        _policyStatusLabel = AppTheme.CreateLabel(
            _writeControlsEnabled ? "自动策略未配置" : "写入锁定",
            AppTheme.Small,
            AppTheme.TextMuted,
            ContentAlignment.MiddleRight);
        _policyStatusLabel.Size = new Size(190, 28);
        _policyStatusLabel.Location = new Point(actionRow.Width - 190, 1);
        _policyStatusLabel.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        actionRow.Resize += delegate
        {
            _policyStatusLabel.Location = new Point(
                Math.Max(100, actionRow.ClientSize.Width - 190),
                1);
        };
        actionRow.Controls.Add(_policyStatusLabel);
        layout.Controls.Add(actionRow, 0, 2);
        SetPolicyButtonEnabled(false);
        return panel;
    }

    private static NumericEntry CreatePolicyInput()
    {
        NumericEntry input = new()
        {
            Minimum = 5,
            Maximum = 60,
            Value = 12,
            Width = 72,
            Margin = new Padding(4, 1, 2, 0)
        };
        input.Font = new Font("Microsoft YaHei UI", 9F, FontStyle.Bold);
        input.TextAlign = HorizontalAlignment.Right;
        return input;
    }

    private static Control CreateMetric(string title, out Label value)
    {
        TableLayoutPanel metric = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 2, 12, 2)
        };
        metric.RowStyles.Add(new RowStyle(SizeType.Absolute, 20));
        metric.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        Label caption = AppTheme.CreateLabel(title, AppTheme.Small, AppTheme.TextMuted);
        caption.Dock = DockStyle.Fill;
        metric.Controls.Add(caption, 0, 0);

        value = AppTheme.CreateLabel("--", AppTheme.BodyBold, AppTheme.Text);
        value.Dock = DockStyle.Fill;
        value.AutoEllipsis = true;
        metric.Controls.Add(value, 0, 1);
        return metric;
    }

    private void BuildTray()
    {
        _trayMenu = new ContextMenuStrip
        {
            ShowImageMargin = false,
            Font = AppTheme.Body
        };
        _trayStatusItem = new ToolStripMenuItem("当前：等待遥测")
        {
            Enabled = false,
            Font = AppTheme.BodyBold
        };
        _trayMenu.Items.Add(_trayStatusItem);
        _trayMenu.Items.Add(new ToolStripSeparator());

        ToolStripMenuItem openItem = new("打开 AMD Mobile Power")
        {
            Font = AppTheme.BodyBold
        };
        openItem.Click += delegate { ShowFromTray(); };
        _trayMenu.Items.Add(openItem);

        ToolStripMenuItem refreshItem = new("刷新状态");
        refreshItem.Click += async delegate { await RefreshSnapshotAsync(manual: true); };
        _trayMenu.Items.Add(refreshItem);

        ToolStripMenuItem modeItem = new("界面模式");
        _traySimpleModeItem = new ToolStripMenuItem("简洁模式");
        _traySimpleModeItem.Click += delegate { SwitchDisplayMode(UiMode.Simple); };
        modeItem.DropDownItems.Add(_traySimpleModeItem);
        _trayAdvancedModeItem = new ToolStripMenuItem("高级模式");
        _trayAdvancedModeItem.Click += delegate { SwitchDisplayMode(UiMode.Advanced); };
        modeItem.DropDownItems.Add(_trayAdvancedModeItem);
        _trayMenu.Items.Add(modeItem);

        _trayTopMostItem = new ToolStripMenuItem("窗口置顶");
        _trayTopMostItem.Click += delegate { ToggleTopMost(); };
        _trayMenu.Items.Add(_trayTopMostItem);

        ToolStripMenuItem diagnosticsItem = new("导出诊断...");
        diagnosticsItem.Click += async delegate { await ExportDiagnosticsAsync(); };
        _trayMenu.Items.Add(diagnosticsItem);
        _trayMenu.Items.Add(new ToolStripSeparator());

        for (int index = 0; index < _presets.Length; index++)
        {
            int selectedIndex = index;
            ToolStripMenuItem item = new($"{_presets[index]} W");
            item.Click += async delegate { await ApplyPresetAsync(selectedIndex); };
            _trayMenu.Items.Add(item);
            _trayPresetItems.Add(item);
        }
        _trayMenu.Items.Add(new ToolStripSeparator());

        ToolStripMenuItem hideItem = new("隐藏到托盘");
        hideItem.Click += delegate { HideToTray(); };
        _trayMenu.Items.Add(hideItem);

        ToolStripMenuItem exitItem = new("退出");
        exitItem.Click += delegate
        {
            _exitRequested = true;
            Close();
        };
        _trayMenu.Items.Add(exitItem);

        _notifyIcon = new NotifyIcon
        {
            Icon = _trayIcon,
            Text = "AMD Mobile Power",
            ContextMenuStrip = _trayMenu,
            Visible = true
        };
        _notifyIcon.MouseClick += delegate (object? sender, MouseEventArgs eventArgs)
        {
            if (eventArgs.Button == MouseButtons.Left)
            {
                ShowFromTray();
            }
        };
        _notifyIcon.DoubleClick += delegate { ShowFromTray(); };
        _notifyIcon.BalloonTipClicked += delegate { ShowFromTray(); };
        UpdatePresetButtons();
        UpdateDisplayModeControls();
    }

    private async Task RefreshSnapshotAsync(bool manual)
    {
        if (_refreshing || _applying || _lifetime.IsCancellationRequested)
        {
            return;
        }

        _refreshing = true;
        try
        {
            WorkerSnapshot snapshot = await _worker
                .GetSnapshotAsync(_lifetime.Token)
                .ConfigureAwait(true);
            _lastSnapshot = snapshot;
            ApplySnapshot(snapshot);
            bool wasConnected = _connected;
            SetConnectionState(connected: true);
            if (!wasConnected)
            {
                ShowStatus("worker 已连接，状态已更新", StatusKind.Normal);
            }
            if (manual)
            {
                ShowStatus("状态已刷新", StatusKind.Normal);
            }
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested)
        {
        }
        catch (Exception error)
        {
            AppDiagnostics.Gui.Error("Snapshot refresh failed.", error);
            SetConnectionState(connected: false);
            ShowStatus("连接失败：" + error.Message, StatusKind.Error);
            SetApplyEnabled(false);
        }
        finally
        {
            _refreshing = false;
        }
    }

    private void ApplySnapshot(WorkerSnapshot snapshot)
    {
        PlatformCapability platform = snapshot.Platform;
        TelemetrySnapshot telemetry = snapshot.Telemetry;
        int minimum = snapshot.MatchedProfile?.MinimumWatts ?? 5;
        int maximum = snapshot.MatchedProfile?.MaximumWatts ?? 60;

        UpdateHeaderPlatformText();
        _profileValue.Text = ShortProfileName(snapshot.MatchedProfile?.DisplayName) ?? "通用检测";
        _rangeValue.Text = $"{minimum}-{maximum} W";

        double? current = telemetry.StapmValueWatts;
        _currentPower.Text = FormatNumber(current);
        _simpleCurrentPower.Text = $"{FormatNumber(current)} W";
        _stapmValue.Text = FormatPair(telemetry.StapmValueWatts, telemetry.StapmLimitWatts);
        _fastValue.Text = FormatPair(telemetry.FastValueWatts, telemetry.FastLimitWatts);
        _slowValue.Text = FormatPair(telemetry.SlowValueWatts, telemetry.SlowLimitWatts);
        _temperatureValue.Text = FormatPair(
            telemetry.TctlValueCelsius,
            telemetry.TctlLimitCelsius,
            "°C");
        _simpleStapmValue.Text = FormatReading(telemetry.StapmValueWatts, "W");
        _simpleStapmLimitValue.Text = FormatLimit(telemetry.StapmLimitWatts, "W");
        _simpleFastValue.Text = FormatReading(telemetry.FastValueWatts, "W");
        _simpleFastLimitValue.Text = FormatLimit(telemetry.FastLimitWatts, "W");
        _simpleSlowValue.Text = FormatReading(telemetry.SlowValueWatts, "W");
        _simpleSlowLimitValue.Text = FormatLimit(telemetry.SlowLimitWatts, "W");
        _simpleTemperatureValue.Text = FormatReading(telemetry.TctlValueCelsius, "°C");
        _simpleTemperatureLimitValue.Text = FormatLimit(
            telemetry.TctlLimitCelsius,
            "°C");

        _powerBar.Maximum = maximum;
        _powerBar.Value = current ?? 0;
        _powerBar.Warning = telemetry.PowerLine == PowerLineState.Battery;
        if (_simplePowerBar is not null)
        {
            _simplePowerBar.Maximum = maximum;
            _simplePowerBar.Value = current ?? 0;
            _simplePowerBar.Warning = telemetry.PowerLine == PowerLineState.Battery;
        }

        bool battery = telemetry.PowerLine == PowerLineState.Battery;
        string powerLineText = DescribePowerLine(telemetry.PowerLine);
        _powerLineBadge.Text = powerLineText;
        _powerLineBadge.BackColor = battery ? AppTheme.BatterySoft : AppTheme.AccentSoft;
        _powerLineBadge.ForeColor = battery ? AppTheme.Battery : AppTheme.Accent;
        _currentPower.ForeColor = battery ? AppTheme.Battery : AppTheme.Accent;
        if (_simplePowerLineBadge is not null)
        {
            _simplePowerLineBadge.Text = powerLineText;
            _simplePowerLineBadge.BackColor = _powerLineBadge.BackColor;
            _simplePowerLineBadge.ForeColor = _powerLineBadge.ForeColor;
        }
        _simpleCurrentPower.ForeColor = _currentPower.ForeColor;

        ConfigureInputs(minimum, maximum);
        _simpleRangeLabel.Text = $"{minimum}-{maximum} W";
        ConfigurePolicyInputs(minimum, maximum, platform.IsSupported);
        TryRestoreSavedPowerPolicy(platform);
        UpdatePresetButtons();
        UpdatePresetSelection();
        UpdateApplyButtonText();

        SetApplyEnabled(
            _writeControlsEnabled &&
            platform.IsSupported &&
            platform.Limits.SupportsAny);
        _writeStateLabel.Text = platform.IsSupported
            ? (_writeControlsEnabled ? "写入已解锁" : "只读模式")
            : "平台不支持写入";
        _writeStateLabel.ForeColor = platform.IsSupported
            ? AppTheme.TextMuted
            : AppTheme.Error;
        _simpleWriteStateLabel.Text = platform.IsSupported
            ? (_writeControlsEnabled ? "写入已解锁" : "只读模式")
            : "平台不支持";
        _simpleWriteStateLabel.ForeColor = platform.IsSupported
            ? (_writeControlsEnabled ? AppTheme.Accent : AppTheme.TextMuted)
            : AppTheme.Error;
        _simpleWriteStateLabel.BackColor = !platform.IsSupported
            ? AppTheme.ErrorSoft
            : _writeControlsEnabled
                ? AppTheme.AccentSoft
                : AppTheme.Border;

        string line = powerLineText;
        DateTimeOffset updatedAt = telemetry.UpdatedAt ?? DateTimeOffset.Now;
        _updatedLabel.Text = $"更新于 {updatedAt:HH:mm:ss} · {line}";
        _trayStatusItem.Text = $"当前：{line} · {FormatNumber(current)} W";
        _notifyIcon.Text = $"AMD Mobile Power | {line} | {FormatNumber(current)} W";

        if (platform.UnsupportedReason is { Length: > 0 } reason)
        {
            ShowStatus(reason, StatusKind.Error);
        }
    }

    private void ConfigureInputs(int minimum, int maximum)
    {
        _syncingTargets = true;
        try
        {
            foreach (NumericEntry input in _limitInputs)
            {
                input.Minimum = minimum;
                input.Maximum = maximum;
            }
            _simpleTargetInput.Minimum = minimum;
            _simpleTargetInput.Maximum = maximum;

            if (_inputsInitialized)
            {
                foreach (NumericEntry input in _limitInputs)
                {
                    input.Value = Math.Clamp(input.Value, minimum, maximum);
                }
                _simpleTargetInput.Value = Math.Clamp(
                    _simpleTargetInput.Value,
                    minimum,
                    maximum);
                return;
            }

            int initial = Math.Clamp(_presets[0], minimum, maximum);
            foreach (NumericEntry input in _limitInputs)
            {
                input.Value = initial;
            }
            _simpleTargetInput.Value = initial;
            _inputsInitialized = true;
        }
        finally
        {
            _syncingTargets = false;
        }
    }

    private void ConfigurePolicyInputs(int minimum, int maximum, bool platformSupported)
    {
        _batteryPolicyInput.Minimum = minimum;
        _batteryPolicyInput.Maximum = maximum;
        _acPolicyInput.Minimum = minimum;
        _acPolicyInput.Maximum = maximum;

        if (!_policyInputsInitialized)
        {
            _batteryPolicyInput.Value = Math.Clamp(
                _storedPolicy?.BatteryWatts ?? _presets[0],
                minimum,
                maximum);
            _acPolicyInput.Value = Math.Clamp(
                _storedPolicy?.AcWatts ?? _presets[2],
                minimum,
                maximum);
            _autoPolicyCheckBox.Checked = _storedPolicy?.Enabled == true;
            _policyInputsInitialized = true;
        }
        else
        {
            _batteryPolicyInput.Value = Math.Clamp(
                _batteryPolicyInput.Value,
                minimum,
                maximum);
            _acPolicyInput.Value = Math.Clamp(
                _acPolicyInput.Value,
                minimum,
                maximum);
        }

        bool enabled = _writeControlsEnabled && platformSupported;
        _autoPolicyCheckBox.Enabled = enabled;
        _batteryPolicyInput.Enabled = enabled;
        _acPolicyInput.Enabled = enabled;
        SetPolicyButtonEnabled(enabled);
        if (!enabled)
        {
            _policyStatusLabel.Text = platformSupported ? "写入锁定" : "平台不支持";
            _policyStatusLabel.ForeColor = platformSupported
                ? AppTheme.TextMuted
                : AppTheme.Error;
        }
    }

    private async Task ApplyPresetAsync(int index)
    {
        int watts = _presets[index];
        SetUniformTarget(watts);
        UpdatePresetSelection();
        if (_writeControlsEnabled && _lastSnapshot?.Platform.IsSupported == true)
        {
            await ApplyCurrentTargetAsync();
        }
    }

    private async Task ApplySimpleTargetAsync()
    {
        int watts = (int)_simpleTargetInput.Value;
        PowerLimitTarget target = PowerLimitTarget.Uniform(watts);
        SetUniformTarget(watts);
        UpdatePresetSelection();
        await ApplyTargetAsync(target);
    }

    private async Task ApplyCurrentTargetAsync()
    {
        if (!_writeControlsEnabled || _lastSnapshot is null)
        {
            ShowStatus("写入控件当前处于锁定状态", StatusKind.Warning);
            return;
        }

        PowerLimitTarget target = new(
            (int)_limitInputs[0].Value,
            (int)_limitInputs[1].Value,
            (int)_limitInputs[2].Value);
        SyncSimpleTargetFromAdvanced();
        await ApplyTargetAsync(target);
    }

    private async Task ApplyTargetAsync(PowerLimitTarget target)
    {
        if (!_writeControlsEnabled ||
            _lastSnapshot is not { Platform.IsSupported: true } ||
            !_lastSnapshot.Platform.Limits.SupportsAny)
        {
            ShowStatus("写入控件当前处于锁定状态", StatusKind.Warning);
            return;
        }

        _applying = true;
        SetApplyEnabled(false);
        _applyButton.Text = "正在应用...";
        _simpleApplyButton.Text = "正在应用...";
        ShowStatus("正在写入并等待回读...", StatusKind.Warning);
        AppDiagnostics.Gui.Info(
            $"Applying target {target.StapmWatts}/{target.FastWatts}/{target.SlowWatts} W.");
        try
        {
            PowerLimitApplicationResult result = await _worker
                .ApplyTargetAsync(target, _lifetime.Token)
                .ConfigureAwait(true);
            if (result.HasFirmwareClamp)
            {
                bool fastOrSlowAdjusted = result.Readbacks.Any(readback =>
                    readback.Kind != PowerLimitKind.Stapm &&
                    readback.EffectiveWatts is { } effective &&
                    Math.Abs(effective - readback.RequestedWatts) > 0.75);
                ShowStatus(
                    fastOrSlowAdjusted
                        ? "写入完成，但固件限制了部分目标值"
                        : "Fast/Slow 已生效，STAPM 由 BIOS 动态调整",
                    StatusKind.Warning);
                AppDiagnostics.Gui.Warning(
                    $"Target applied with firmware clamp. " +
                    $"Requested={target.StapmWatts}/{target.FastWatts}/{target.SlowWatts} W.");
            }
            else if (result.HasStapmWarning)
            {
                ShowStatus(
                    "Fast/Slow 已生效，STAPM 未接受写入（不影响功率上限）",
                    StatusKind.Warning);
                AppDiagnostics.Gui.Warning(
                    "Fast/Slow applied; STAPM write was rejected or unavailable.");
            }
            else
            {
                ShowStatus("三项功耗限制已应用并完成回读", StatusKind.Normal);
                AppDiagnostics.Gui.Info("Target applied with matching read-back.");
            }
            await RefreshSnapshotAsync(manual: false);
        }
        catch (Exception error)
        {
            AppDiagnostics.Gui.Error("Power-limit apply failed.", error);
            ShowStatus(
                "应用失败：" + TranslatePowerWriteError(error.Message),
                StatusKind.Error);
        }
        finally
        {
            _applying = false;
            UpdateApplyButtonText();
            SetApplyEnabled(
                _writeControlsEnabled &&
                _lastSnapshot?.Platform.IsSupported == true);
        }
    }

    private async Task ExportDiagnosticsAsync()
    {
        string defaultDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "AmdMobilePower",
            "diagnostics");
        Directory.CreateDirectory(defaultDirectory);
        using SaveFileDialog dialog = new()
        {
            Title = "导出 AMD Mobile Power 诊断",
            Filter = "JSON 文件 (*.json)|*.json|所有文件 (*.*)|*.*",
            AddExtension = true,
            DefaultExt = "json",
            FileName = $"amd-mobile-power-diagnostics-{DateTime.Now:yyyyMMdd-HHmmss}.json",
            InitialDirectory = defaultDirectory
        };
        if (dialog.ShowDialog(this) != DialogResult.OK)
        {
            return;
        }

        try
        {
            WorkerDiagnostics diagnostics = await _worker
                .ExportDiagnosticsAsync(_lifetime.Token)
                .ConfigureAwait(true);
            string json = PublicDiagnosticsReport.Serialize(diagnostics);
            await File.WriteAllTextAsync(dialog.FileName, json, _lifetime.Token)
                .ConfigureAwait(true);
            ShowStatus($"诊断已导出：{dialog.FileName}", StatusKind.Normal);
        }
        catch (Exception error)
        {
            ShowStatus("导出诊断失败：" + error.Message, StatusKind.Error);
        }
    }

    private async Task SavePowerPolicyAsync()
    {
        if (!_writeControlsEnabled || _lastSnapshot?.Platform.IsSupported != true)
        {
            ShowStatus("写入控件当前处于锁定状态", StatusKind.Warning);
            return;
        }

        SetPolicyButtonEnabled(false);
        try
        {
            PowerPolicySettings settings = new(
                Enabled: _autoPolicyCheckBox.Checked,
                BatteryTarget: PowerLimitTarget.Uniform((int)_batteryPolicyInput.Value),
                AcTarget: PowerLimitTarget.Uniform((int)_acPolicyInput.Value));
            PowerPolicyState state = await _worker
                .SetPowerPolicyAsync(settings, _lifetime.Token)
                .ConfigureAwait(true);
            _storedPolicy = new StoredPowerPolicy(
                settings.Enabled,
                settings.BatteryTarget.StapmWatts,
                settings.AcTarget.StapmWatts);
            UiStateStore.SavePowerPolicy(_storedPolicy);
            _storedPolicyRestored = settings.Enabled;
            _policyStatusLabel.Text = state.Settings?.Enabled == true
                ? $"电池 {settings.BatteryTarget.StapmWatts}W · 电源 {settings.AcTarget.StapmWatts}W"
                : "自动策略已关闭";
            _policyStatusLabel.ForeColor = AppTheme.TextMuted;
            ShowStatus(
                state.Settings?.Enabled == true ? "自动电源策略已启用" : "自动电源策略已关闭",
                StatusKind.Normal);
        }
        catch (Exception error)
        {
            ShowStatus("保存自动策略失败：" + error.Message, StatusKind.Error);
        }
        finally
        {
            SetPolicyButtonEnabled(
                _writeControlsEnabled &&
                _lastSnapshot?.Platform.IsSupported == true);
        }
    }

    private void TryRestoreSavedPowerPolicy(PlatformCapability platform)
    {
        if (!_writeControlsEnabled ||
            !platform.IsSupported ||
            _storedPolicy is not { Enabled: true } savedPolicy ||
            _storedPolicyRestored)
        {
            return;
        }

        _storedPolicyRestored = true;
        _ = RestoreSavedPowerPolicyAsync(savedPolicy);
    }

    private async Task RestoreSavedPowerPolicyAsync(StoredPowerPolicy savedPolicy)
    {
        try
        {
            PowerPolicySettings settings = new(
                Enabled: true,
                BatteryTarget: PowerLimitTarget.Uniform(savedPolicy.BatteryWatts),
                AcTarget: PowerLimitTarget.Uniform(savedPolicy.AcWatts));
            _ = await _worker
                .SetPowerPolicyAsync(settings, _lifetime.Token)
                .ConfigureAwait(true);
            _autoPolicyCheckBox.Checked = true;
            _policyStatusLabel.Text =
                $"电池 {savedPolicy.BatteryWatts}W · 电源 {savedPolicy.AcWatts}W";
            _policyStatusLabel.ForeColor = AppTheme.TextMuted;
        }
        catch (Exception error)
        {
            ShowStatus("恢复自动策略失败：" + error.Message, StatusKind.Error);
        }
    }

    private void SetPolicyButtonEnabled(bool enabled)
    {
        _savePolicyButton.Enabled = enabled;
        _savePolicyButton.BackColor = enabled
            ? AppTheme.Surface
            : Color.FromArgb(210, 217, 213);
        _savePolicyButton.ForeColor = enabled
            ? AppTheme.Text
            : Color.FromArgb(110, 121, 117);
        _savePolicyButton.FlatAppearance.MouseOverBackColor = enabled
            ? AppTheme.SurfaceMuted
            : Color.FromArgb(210, 217, 213);
    }

    private void ShowPresetEditor()
    {
        int minimum = _lastSnapshot?.MatchedProfile?.MinimumWatts ?? 5;
        int maximum = _lastSnapshot?.MatchedProfile?.MaximumWatts ?? 60;
        using PresetEditorForm dialog = new(_presets, minimum, maximum);
        if (dialog.ShowDialog(this) != DialogResult.OK)
        {
            return;
        }

        try
        {
            _presets = dialog.Presets;
            UiStateStore.SavePresets(_presets);
            UpdatePresetButtons();
            UpdatePresetSelection();
        }
        catch (Exception error)
        {
            ShowStatus("保存预设失败：" + error.Message, StatusKind.Error);
        }
    }

    private void SetUniformTarget(int watts)
    {
        _syncingTargets = true;
        try
        {
            foreach (NumericEntry input in _limitInputs)
            {
                input.Value = Math.Clamp(watts, (int)input.Minimum, (int)input.Maximum);
            }
            _simpleTargetInput.Value = Math.Clamp(
                watts,
                (int)_simpleTargetInput.Minimum,
                (int)_simpleTargetInput.Maximum);
        }
        finally
        {
            _syncingTargets = false;
        }
    }

    private void UpdatePresetButtons()
    {
        int maximum = _lastSnapshot?.MatchedProfile?.MaximumWatts ?? 60;
        for (int index = 0; index < _presetButtons.Length; index++)
        {
            int watts = _presets[index];
            _presetButtons[index].Text = $"{watts} W";
            _presetButtons[index].Tag = watts;
            bool supported = watts <= maximum;
            _presetButtons[index].Enabled = supported;
            if (_simplePresetButtons[index] is { } simpleButton)
            {
                simpleButton.Text = $"{watts} W";
                simpleButton.Tag = watts;
                simpleButton.Enabled = supported;
            }
            if (index < _trayPresetItems.Count)
            {
                _trayPresetItems[index].Text = $"{watts} W";
                _trayPresetItems[index].Enabled = supported;
            }
        }
    }

    private void UpdatePresetSelection()
    {
        if (_presetButtons.Any(button => button is null))
        {
            return;
        }

        for (int index = 0; index < _presetButtons.Length; index++)
        {
            bool selected = _limitInputs.All(
                input => (int)input.Value == _presets[index]);
            Button button = _presetButtons[index];
            button.BackColor = selected ? AppTheme.Accent : AppTheme.Surface;
            button.ForeColor = selected ? Color.White : AppTheme.Text;
            button.FlatAppearance.BorderSize = selected ? 0 : 1;
            button.FlatAppearance.BorderColor = AppTheme.Border;
            button.FlatAppearance.MouseOverBackColor = selected
                ? AppTheme.AccentHover
                : AppTheme.SurfaceMuted;
            button.FlatAppearance.MouseDownBackColor = selected
                ? AppTheme.AccentHover
                : AppTheme.Border;
        }

        if (_simplePresetButtons.Any(button => button is null))
        {
            return;
        }

        for (int index = 0; index < _simplePresetButtons.Length; index++)
        {
            bool selected = _limitInputs.All(
                input => (int)input.Value == _presets[index]);
            Button button = _simplePresetButtons[index];
            bool enabled = button.Enabled;
            button.BackColor = !enabled
                ? AppTheme.DisabledBackground
                : selected
                    ? AppTheme.AccentSoft
                    : AppTheme.Surface;
            button.ForeColor = !enabled
                ? AppTheme.DisabledText
                : selected
                    ? AppTheme.AccentHover
                    : AppTheme.Text;
            button.FlatAppearance.BorderSize = 1;
            button.FlatAppearance.BorderColor = selected && enabled
                ? AppTheme.Accent
                : AppTheme.Border;
            button.FlatAppearance.MouseOverBackColor = selected
                ? AppTheme.AccentSoft
                : AppTheme.SurfaceMuted;
            button.FlatAppearance.MouseDownBackColor = selected
                ? AppTheme.Border
                : AppTheme.Border;
        }
    }

    private void UpdateApplyButtonText()
    {
        if (_applyButton is null || _limitInputs.Any(input => input is null))
        {
            return;
        }

        bool uniform = _limitInputs
            .Select(input => (int)input.Value)
            .Distinct()
            .Count() == 1;
        _applyButton.Text = uniform
            ? $"应用 {_limitInputs[0].Value:0} W"
            : "应用三项限制";
        if (_simpleApplyButton is not null)
        {
            _simpleApplyButton.Text = $"应用 {_simpleTargetInput.Value:0} W";
        }
        UpdateSimpleLimitSummary();
    }

    private void UpdateSimpleLimitSummary()
    {
        if (_simpleLimitSummary is null || _simpleTargetInput is null)
        {
            return;
        }

        string limit = FormatNumber(_lastSnapshot?.Telemetry.StapmLimitWatts);
        string powerLine = DescribePowerLine(
            _lastSnapshot?.Telemetry.PowerLine ?? PowerLineState.Unknown);
        _simpleLimitSummary.Text = $"动态上限 {limit} W · {powerLine}";
    }

    private static string DescribePowerLine(PowerLineState powerLine)
    {
        return powerLine switch
        {
            PowerLineState.Ac => "电源",
            PowerLineState.Battery => "电池",
            _ => "电源未知"
        };
    }

    private void SetConnectionState(bool connected)
    {
        bool changed = _connected != connected;
        _connected = connected;
        UpdateConnectionBadgeText();
        _connectionBadge.BackColor = connected
            ? AppTheme.Accent
            : AppTheme.Error;
        if (changed)
        {
            AppDiagnostics.Gui.Info(
                connected ? "Worker connection established." : "Worker connection lost.");
        }
    }

    private static Button CreateHeaderModeButton(string text)
    {
        Button button = new()
        {
            Text = text,
            Size = new Size(56, 28),
            FlatStyle = FlatStyle.Flat,
            Font = AppTheme.SmallBold,
            Cursor = Cursors.Hand,
            TabStop = true,
            UseVisualStyleBackColor = false,
            AccessibleName = text + "模式"
        };
        button.FlatAppearance.BorderSize = 0;
        return button;
    }

    private void LayoutHeader()
    {
        if (_headerHost is null ||
            _headerTitle is null ||
            _headerPlatform is null ||
            _headerModeSwitch is null ||
            _connectionBadge is null)
        {
            return;
        }

        bool simple = _uiMode == UiMode.Simple;
        _headerIcon.Visible = !simple;
        _connectionBadge.Visible = !simple;
        _headerTitle.Text = simple ? "AMD Power" : "AMD Mobile Power";
        _headerTitle.Font = simple ? AppTheme.CompactTitle : AppTheme.Title;
        _headerTitle.Location = new Point(simple ? 18 : 86, simple ? 4 : 12);
        _headerTitle.Height = simple ? 24 : 30;
        _headerPlatform.Location = new Point(simple ? 18 : 88, simple ? 27 : 43);
        _headerPlatform.Height = simple ? 20 : 22;
        int textWidth = simple
            ? Math.Max(120, _headerHost.ClientSize.Width - 224)
            : Math.Max(180, _headerHost.ClientSize.Width - 450);
        _headerTitle.Width = textWidth;
        _headerPlatform.Width = textWidth;
        UpdateHeaderPlatformText();

        if (simple)
        {
            _headerModeSwitch.Location = new Point(
                Math.Max(16, _headerHost.ClientSize.Width - 198),
                10);
            _topMostButton.Location = new Point(
                Math.Max(16, _headerHost.ClientSize.Width - 72),
                10);
        }
        else
        {
            _headerModeSwitch.Location = new Point(
                Math.Max(24, _headerHost.ClientSize.Width - 338),
                24);
            _topMostButton.Location = new Point(
                Math.Max(24, _headerHost.ClientSize.Width - 212),
                24);
            _connectionBadge.Size = new Size(118, 32);
            _connectionBadge.Location = new Point(
                Math.Max(24, _headerHost.ClientSize.Width - 142),
                24);
        }
    }

    private void UpdateHeaderPlatformText()
    {
        if (_headerPlatform is null)
        {
            return;
        }

        if (_lastSnapshot is not { } snapshot)
        {
            _headerPlatform.Text = "正在读取平台...";
            return;
        }

        string processorName = ShortProcessorName(snapshot.Platform.Cpu.ProcessorName);
        string smu = snapshot.Platform.Cpu.SmuBiosVersion ?? "--";
        _headerPlatform.Text = _uiMode == UiMode.Simple
            ? $"{processorName} · SMU {smu}"
            : $"{processorName} · SMU {smu} · PMT {snapshot.Platform.Cpu.PmTableVersion ?? "--"}";
    }

    private void SwitchDisplayMode(UiMode mode)
    {
        if (_uiMode == mode)
        {
            return;
        }

        if (WindowState == FormWindowState.Maximized)
        {
            WindowState = FormWindowState.Normal;
        }

        _uiMode = mode;
        AppDiagnostics.Gui.Info($"Display mode changed to {mode}.");
        FormBorderStyle = mode == UiMode.Simple
            ? FormBorderStyle.FixedSingle
            : FormBorderStyle.Sizable;
        MaximizeBox = mode == UiMode.Advanced;
        ShowIcon = mode == UiMode.Advanced;
        if (mode == UiMode.Simple)
        {
            SyncSimpleTargetFromAdvanced();
            _simpleBody.Visible = true;
            _advancedBody.Visible = false;
            _footerHost.Visible = false;
            _simpleBody.BringToFront();
        }
        else
        {
            _simpleBody.Visible = false;
            _advancedBody.Visible = true;
            _footerHost.Visible = true;
            _advancedBody.BringToFront();
        }

        UpdateDisplayModeControls();
        _rootLayout.RowStyles[0].Height = mode == UiMode.Simple ? 52 : 82;
        _rootLayout.RowStyles[2].Height = mode == UiMode.Simple ? 0 : 34;
        if (IsHandleCreated)
        {
            BeginInvoke(ApplyDpiCompensatedWindowSize);
        }

        try
        {
            UiStateStore.SaveUiMode(mode);
        }
        catch (Exception error)
        {
            ShowStatus("界面模式保存失败：" + error.Message, StatusKind.Warning);
        }
    }

    private void ToggleTopMost()
    {
        _topMost = !_topMost;
        TopMost = _topMost;
        AppDiagnostics.Gui.Info($"Always-on-top changed to {_topMost}.");
        UpdateDisplayModeControls();
        try
        {
            UiStateStore.SaveTopMost(_topMost);
        }
        catch (Exception error)
        {
            ShowStatus("置顶状态保存失败：" + error.Message, StatusKind.Warning);
        }
    }

    private void UpdateDisplayModeControls()
    {
        if (_simpleModeButton is null || _advancedModeButton is null)
        {
            return;
        }

        StyleHeaderModeButton(_simpleModeButton, _uiMode == UiMode.Simple);
        StyleHeaderModeButton(_advancedModeButton, _uiMode == UiMode.Advanced);
        StyleHeaderModeButton(_topMostButton, _topMost);
        UpdateConnectionBadgeText();
        LayoutHeader();
        if (_traySimpleModeItem is not null)
        {
            _traySimpleModeItem.Checked = _uiMode == UiMode.Simple;
        }
        if (_trayAdvancedModeItem is not null)
        {
            _trayAdvancedModeItem.Checked = _uiMode == UiMode.Advanced;
        }
        if (_trayTopMostItem is not null)
        {
            _trayTopMostItem.Checked = _topMost;
        }
    }

    private void UpdateConnectionBadgeText()
    {
        if (_connectionBadge is null)
        {
            return;
        }

        _connectionBadge.Text = _uiMode == UiMode.Simple
            ? (_connected ? "在线" : "离线")
            : (_connected ? "worker 在线" : "worker 离线");
    }

    private static void StyleHeaderModeButton(Button button, bool selected)
    {
        button.BackColor = selected
            ? AppTheme.Accent
            : Color.FromArgb(48, 64, 61);
        button.ForeColor = selected
            ? Color.White
            : AppTheme.HeaderMuted;
        button.FlatAppearance.MouseOverBackColor = selected
            ? AppTheme.AccentHover
            : Color.FromArgb(62, 80, 76);
        button.FlatAppearance.MouseDownBackColor = selected
            ? AppTheme.AccentHover
            : Color.FromArgb(72, 91, 87);
    }

    private void SyncAdvancedTargetsFromSimple()
    {
        if (_simpleTargetInput is null || _limitInputs.Any(input => input is null))
        {
            return;
        }

        _syncingTargets = true;
        try
        {
            foreach (NumericEntry input in _limitInputs)
            {
                input.Value = Math.Clamp(
                    (int)_simpleTargetInput.Value,
                    (int)input.Minimum,
                    (int)input.Maximum);
            }
        }
        finally
        {
            _syncingTargets = false;
        }
    }

    private void SyncSimpleTargetFromAdvanced()
    {
        if (_simpleTargetInput is null || _limitInputs[0] is null)
        {
            return;
        }

        _syncingTargets = true;
        try
        {
            _simpleTargetInput.Value = Math.Clamp(
                (int)_limitInputs[0].Value,
                (int)_simpleTargetInput.Minimum,
                (int)_simpleTargetInput.Maximum);
        }
        finally
        {
            _syncingTargets = false;
        }
    }

    private void ApplyDpiCompensatedWindowSize()
    {
        float scale = Math.Max(1F, DeviceDpi / 96F);
        Size minimum = _uiMode == UiMode.Simple
            ? Size.Empty
            : new Size(900, 650);
        Size requested = _uiMode == UiMode.Simple
            ? new Size(560, 400)
            : new Size(1000, 700);
        MinimumSize = _uiMode == UiMode.Simple
            ? Size.Empty
            : ScaleWindowSize(minimum, scale);
        Size desired = ScaleWindowSize(requested, scale);
        Rectangle workingArea = Screen.FromControl(this).WorkingArea;
        desired.Width = Math.Min(desired.Width, workingArea.Width);
        desired.Height = Math.Min(desired.Height, workingArea.Height);
        ClientSize = desired;

        Location = new Point(
            workingArea.Left + Math.Max(0, (workingArea.Width - Width) / 2),
            workingArea.Top + Math.Max(0, (workingArea.Height - Height) / 2));
    }

    private static Size ScaleWindowSize(Size size, float scale)
    {
        return new Size(
            (int)Math.Round(size.Width * scale),
            (int)Math.Round(size.Height * scale));
    }

    private void SetApplyEnabled(bool enabled)
    {
        _applyButton.Enabled = enabled;
        _applyButton.BackColor = enabled ? AppTheme.Accent : Color.FromArgb(205, 213, 209);
        _applyButton.ForeColor = enabled ? Color.White : Color.FromArgb(107, 119, 115);
        _applyButton.FlatAppearance.MouseOverBackColor = enabled
            ? AppTheme.AccentHover
            : Color.FromArgb(205, 213, 209);
        _applyButton.FlatAppearance.MouseDownBackColor = enabled
            ? AppTheme.AccentHover
            : Color.FromArgb(205, 213, 209);
        if (_simpleApplyButton is null)
        {
            return;
        }

        _simpleApplyButton.Enabled = enabled && !_applying;
        _simpleApplyButton.BackColor = enabled
            ? AppTheme.Accent
            : AppTheme.DisabledBackground;
        _simpleApplyButton.ForeColor = enabled
            ? Color.White
            : AppTheme.DisabledText;
        _simpleApplyButton.FlatAppearance.MouseOverBackColor = enabled
            ? AppTheme.AccentHover
            : AppTheme.DisabledBackground;
        _simpleApplyButton.FlatAppearance.MouseDownBackColor = enabled
            ? AppTheme.AccentHover
            : AppTheme.DisabledBackground;
        _simpleApplyButton.Cursor = enabled && !_applying
            ? Cursors.Hand
            : Cursors.Default;
    }

    private void ShowStatus(string text, StatusKind kind)
    {
        _statusLabel.Text = text;
        _simpleStatusLabel.Text = CompactSimpleStatus(text);
        switch (kind)
        {
            case StatusKind.Normal:
                _statusLabel.BackColor = AppTheme.SurfaceMuted;
                _statusLabel.ForeColor = AppTheme.TextMuted;
                _simpleStatusBar.BackColor = AppTheme.SurfaceMuted;
                _simpleStatusLabel.BackColor = Color.Transparent;
                _simpleStatusLabel.ForeColor = AppTheme.TextMuted;
                break;
            case StatusKind.Warning:
                _statusLabel.BackColor = AppTheme.WarningSoft;
                _statusLabel.ForeColor = AppTheme.Warning;
                _simpleStatusBar.BackColor = AppTheme.WarningSoft;
                _simpleStatusLabel.BackColor = Color.Transparent;
                _simpleStatusLabel.ForeColor = AppTheme.Warning;
                break;
            case StatusKind.Error:
                _statusLabel.BackColor = AppTheme.ErrorSoft;
                _statusLabel.ForeColor = AppTheme.Error;
                _simpleStatusBar.BackColor = AppTheme.ErrorSoft;
                _simpleStatusLabel.BackColor = Color.Transparent;
                _simpleStatusLabel.ForeColor = AppTheme.Error;
                break;
        }
    }

    private static string CompactSimpleStatus(string text)
    {
        if (text.Contains("RyzenAdjPowerWorker", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("正在占用 RyzenAdj", StringComparison.OrdinalIgnoreCase))
        {
            return "旧版 RyzenAdj 正在占用，退出后再试";
        }

        if (text.Contains("重启 Windows", StringComparison.OrdinalIgnoreCase))
        {
            return "硬件读取超时，请重启 Windows 后再试";
        }

        if (text.Contains("BIOS/EC", StringComparison.OrdinalIgnoreCase))
        {
            return text.Replace("应用失败：", string.Empty, StringComparison.Ordinal);
        }

        if (text.Length <= 40)
        {
            return text;
        }

        return "操作失败，请打开高级模式查看详情";
    }

    private static string TranslatePowerWriteError(string text)
    {
        Match match = Regex.Match(
            text,
            @"(?<kind>Stapm|Fast|Slow) requested (?<requested>[0-9.]+)W but read back (?<actual>[0-9.]+)W",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        if (!match.Success)
        {
            return text;
        }

        string kind = match.Groups["kind"].Value.ToUpperInvariant();
        decimal requested = decimal.Parse(
            match.Groups["requested"].Value,
            CultureInfo.InvariantCulture);
        decimal actual = decimal.Parse(
            match.Groups["actual"].Value,
            CultureInfo.InvariantCulture);
        return
            $"BIOS/EC 将 {kind} 下限保持在 {actual:0.0}W，无法降到 {requested:0}W";
    }

    private void StartShowListener()
    {
        Thread thread = new((ThreadStart)delegate
        {
            while (!_lifetime.IsCancellationRequested)
            {
                try
                {
                    _showEvent.WaitOne();
                    if (IsDisposed)
                    {
                        break;
                    }
                    if (!IsHandleCreated)
                    {
                        Thread.Sleep(50);
                        continue;
                    }
                    BeginInvoke(ShowFromTray);
                }
                catch
                {
                    break;
                }
            }
        })
        {
            IsBackground = true,
            Name = "AMD Mobile Power show listener"
        };
        thread.Start();
    }

    private void ShowFromTray()
    {
        if (IsDisposed)
        {
            return;
        }
        ShowInTaskbar = true;
        Opacity = 1;
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
        BringToFront();
    }

    private void HideToTray()
    {
        if (IsDisposed || _exitRequested)
        {
            return;
        }
        Hide();
        ShowInTaskbar = false;
        if (!_trayHintShown)
        {
            _notifyIcon.ShowBalloonTip(
                1800,
                "AMD Mobile Power",
                "程序仍在托盘运行。",
                ToolTipIcon.Info);
            _trayHintShown = true;
        }
    }

    private static string FormatNumber(double? value)
    {
        return value is { } number ? number.ToString("0.0", CultureInfo.CurrentCulture) : "--";
    }

    private static string FormatReading(double? value, string unit)
    {
        return value is { } number
            ? $"{number.ToString("0.0", CultureInfo.CurrentCulture)} {unit}"
            : $"-- {unit}";
    }

    private static string FormatLimit(double? value, string unit)
    {
        return value is { } number
            ? $"上限 {number.ToString("0.0", CultureInfo.CurrentCulture)} {unit}"
            : $"上限 -- {unit}";
    }

    private static string FormatPair(double? value, double? limit, string unit = "W")
    {
        string current = value is { } actual
            ? actual.ToString("0.0", CultureInfo.CurrentCulture)
            : "--";
        string maximum = limit is { } effective
            ? effective.ToString("0.0", CultureInfo.CurrentCulture)
            : "--";
        return $"{current} / {maximum} {unit}";
    }

    private static string? ShortProfileName(string? displayName)
    {
        if (string.IsNullOrWhiteSpace(displayName))
        {
            return null;
        }

        const string suffix = " development profile";
        return displayName.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)
            ? displayName[..^suffix.Length]
            : displayName;
    }

    private static string ShortProcessorName(string processorName)
    {
        string shortened = processorName.Replace(
            "AMD ",
            string.Empty,
            StringComparison.OrdinalIgnoreCase);
        int integratedGraphics = shortened.IndexOf(
            " w/",
            StringComparison.OrdinalIgnoreCase);
        return integratedGraphics > 0
            ? shortened[..integratedGraphics].Trim()
            : shortened.Trim();
    }

    private static Icon LoadApplicationIcon()
    {
        string iconPath = Path.Combine(AppContext.BaseDirectory, "assets", "amd-mobile-power.ico");
        if (File.Exists(iconPath))
        {
            return new Icon(iconPath);
        }

        return Icon.ExtractAssociatedIcon(Application.ExecutablePath)
            ?? (Icon)SystemIcons.Application.Clone();
    }

    private static Image? LoadHeaderImage()
    {
        string imagePath = Path.Combine(
            AppContext.BaseDirectory,
            "assets",
            "amd-mobile-power-256.png");
        if (!File.Exists(imagePath))
        {
            return null;
        }

        using FileStream stream = File.OpenRead(imagePath);
        using Image image = Image.FromStream(stream);
        return new Bitmap(image);
    }

    private enum StatusKind
    {
        Normal,
        Warning,
        Error
    }
}
