using System.Globalization;
using System.Text.Json;
using AmdMobilePower.Core.Contracts;
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
    private readonly NumericUpDown[] _limitInputs = new NumericUpDown[3];
    private readonly Button[] _presetButtons = new Button[3];
    private readonly List<ToolStripMenuItem> _trayPresetItems = new(3);
    private StoredPowerPolicy? _storedPolicy;

    private NotifyIcon _notifyIcon = null!;
    private ContextMenuStrip _trayMenu = null!;
    private ToolStripMenuItem _trayStatusItem = null!;
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
    private Button _editPresetButton = null!;
    private Button _savePolicyButton = null!;
    private CheckBox _autoPolicyCheckBox = null!;
    private NumericUpDown _batteryPolicyInput = null!;
    private NumericUpDown _acPolicyInput = null!;
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
    private bool _windowSizeAdjusted;

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
        if (_startHidden)
        {
            BeginInvoke(HideToTray);
        }

        _refreshTimer.Start();
        _ = RefreshSnapshotAsync(manual: false);
    }

    protected override void OnHandleCreated(EventArgs eventArgs)
    {
        base.OnHandleCreated(eventArgs);
        ApplyDpiCompensatedWindowSize();
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
        ShowIcon = true;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(1000, 700);
        MinimumSize = new Size(900, 650);
        BackColor = AppTheme.Background;
        ForeColor = AppTheme.Text;
        Font = AppTheme.Body;
        AutoScaleMode = AutoScaleMode.None;
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
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 82));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        Controls.Add(root);

        root.Controls.Add(BuildHeader(), 0, 0);
        root.Controls.Add(BuildBody(), 0, 1);
        root.Controls.Add(BuildFooter(), 0, 2);

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

        PictureBox icon = new()
        {
            Location = new Point(24, 17),
            Size = new Size(48, 48),
            SizeMode = PictureBoxSizeMode.Zoom,
            Image = _headerImage,
            BackColor = Color.Transparent
        };
        header.Controls.Add(icon);

        Label title = AppTheme.CreateLabel(
            "AMD Mobile Power",
            AppTheme.Title,
            Color.White);
        title.Location = new Point(86, 12);
        title.Size = new Size(Math.Max(220, header.Width - 276), 30);
        title.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        header.Controls.Add(title);

        _headerPlatform = AppTheme.CreateLabel(
            "正在读取平台...",
            AppTheme.Small,
            AppTheme.HeaderMuted);
        _headerPlatform.Location = new Point(88, 43);
        _headerPlatform.Size = new Size(Math.Max(220, header.Width - 276), 22);
        _headerPlatform.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        header.Controls.Add(_headerPlatform);

        _connectionBadge = AppTheme.CreateLabel(
            "等待 worker",
            AppTheme.SmallBold,
            Color.White,
            ContentAlignment.MiddleCenter);
        _connectionBadge.Size = new Size(164, 32);
        _connectionBadge.Location = new Point(Math.Max(24, header.Width - 188), 24);
        _connectionBadge.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _connectionBadge.BackColor = Color.FromArgb(56, 74, 71);
        header.Controls.Add(_connectionBadge);
        header.Resize += delegate
        {
            int textWidth = Math.Max(220, header.ClientSize.Width - 276);
            title.Width = textWidth;
            _headerPlatform.Width = textWidth;
            _connectionBadge.Location = new Point(
                Math.Max(24, header.ClientSize.Width - 188),
                24);
        };

        return header;
    }

    private Control BuildBody()
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

        metrics.Controls.Add(CreateMetric("STAPM", out _stapmValue), 0, 0);
        metrics.Controls.Add(CreateMetric("PPT Fast", out _fastValue), 1, 0);
        metrics.Controls.Add(CreateMetric("PPT Slow", out _slowValue), 0, 1);
        metrics.Controls.Add(CreateMetric("CPU 温度", out _temperatureValue), 1, 1);
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

            NumericUpDown input = new()
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

        _applyButton = AppTheme.CreateButton(
            "应用三项限制",
            primary: true,
            width: 220,
            height: 40);
        _applyButton.Dock = DockStyle.Fill;
        _applyButton.Click += async delegate { await ApplyCurrentTargetAsync(); };
        layout.Controls.Add(_applyButton, 0, 5);
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

        Label version = AppTheme.CreateLabel(
            "v0.1.0 · worker v1",
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

    private static NumericUpDown CreatePolicyInput()
    {
        NumericUpDown input = new()
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

        string processorName = ShortProcessorName(platform.Cpu.ProcessorName);
        _headerPlatform.Text =
            $"{processorName} · SMU {platform.Cpu.SmuBiosVersion ?? "--"} · PMT {platform.Cpu.PmTableVersion ?? "--"}";
        _profileValue.Text = ShortProfileName(snapshot.MatchedProfile?.DisplayName) ?? "通用检测";
        _rangeValue.Text = $"{minimum}-{maximum} W";

        double? current = telemetry.StapmValueWatts;
        _currentPower.Text = FormatNumber(current);
        _stapmValue.Text = FormatPair(telemetry.StapmValueWatts, telemetry.StapmLimitWatts);
        _fastValue.Text = FormatPair(telemetry.FastValueWatts, telemetry.FastLimitWatts);
        _slowValue.Text = FormatPair(telemetry.SlowValueWatts, telemetry.SlowLimitWatts);
        _temperatureValue.Text = FormatPair(
            telemetry.TctlValueCelsius,
            telemetry.TctlLimitCelsius,
            "°C");

        _powerBar.Maximum = maximum;
        _powerBar.Value = current ?? 0;
        _powerBar.Warning = telemetry.PowerLine == PowerLineState.Battery;

        bool battery = telemetry.PowerLine == PowerLineState.Battery;
        _powerLineBadge.Text = telemetry.PowerLine switch
        {
            PowerLineState.Ac => "接入电源",
            PowerLineState.Battery => "电池供电",
            _ => "电源未知"
        };
        _powerLineBadge.BackColor = battery ? AppTheme.BatterySoft : AppTheme.AccentSoft;
        _powerLineBadge.ForeColor = battery ? AppTheme.Battery : AppTheme.Accent;
        _currentPower.ForeColor = battery ? AppTheme.Battery : AppTheme.Accent;

        ConfigureInputs(minimum, maximum, snapshot.MatchedProfile?.DefaultWatts ?? 25);
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

        string line = battery ? "电池" : telemetry.PowerLine == PowerLineState.Ac ? "电源" : "未知电源";
        DateTimeOffset updatedAt = telemetry.UpdatedAt ?? DateTimeOffset.Now;
        _updatedLabel.Text = $"更新于 {updatedAt:HH:mm:ss} · {line}";
        _trayStatusItem.Text = $"当前：{line} · {FormatNumber(current)} W";
        _notifyIcon.Text = $"AMD Mobile Power | {line} | {FormatNumber(current)} W";

        if (platform.UnsupportedReason is { Length: > 0 } reason)
        {
            ShowStatus(reason, StatusKind.Error);
        }
    }

    private void ConfigureInputs(int minimum, int maximum, int defaultWatts)
    {
        foreach (NumericUpDown input in _limitInputs)
        {
            input.Minimum = minimum;
            input.Maximum = maximum;
        }

        if (_inputsInitialized)
        {
            foreach (NumericUpDown input in _limitInputs)
            {
                input.Value = Math.Clamp(input.Value, minimum, maximum);
            }
            return;
        }

        int initial = Math.Clamp(defaultWatts, minimum, maximum);
        foreach (NumericUpDown input in _limitInputs)
        {
            input.Value = initial;
        }
        _inputsInitialized = true;
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
        _applying = true;
        SetApplyEnabled(false);
        _applyButton.Text = "正在应用...";
        ShowStatus("正在写入并等待回读...", StatusKind.Warning);
        try
        {
            PowerLimitApplicationResult result = await _worker
                .ApplyTargetAsync(target, _lifetime.Token)
                .ConfigureAwait(true);
            if (result.HasFirmwareClamp)
            {
                ShowStatus("写入完成，但固件限制了部分目标值", StatusKind.Warning);
            }
            else
            {
                ShowStatus("三项功耗限制已应用并完成回读", StatusKind.Normal);
            }
            await RefreshSnapshotAsync(manual: false);
        }
        catch (Exception error)
        {
            ShowStatus("应用失败：" + error.Message, StatusKind.Error);
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
            JsonSerializerOptions options = new(WorkerProtocol.JsonOptions)
            {
                WriteIndented = true
            };
            string json = JsonSerializer.Serialize(diagnostics, options);
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
        foreach (NumericUpDown input in _limitInputs)
        {
            input.Value = Math.Clamp(watts, (int)input.Minimum, (int)input.Maximum);
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
    }

    private void SetConnectionState(bool connected)
    {
        _connected = connected;
        _connectionBadge.Text = connected ? "worker 已连接" : "worker 离线";
        _connectionBadge.BackColor = connected
            ? AppTheme.Accent
            : AppTheme.Error;
    }

    private void ApplyDpiCompensatedWindowSize()
    {
        if (_windowSizeAdjusted)
        {
            return;
        }

        _windowSizeAdjusted = true;
        float scale = Math.Max(1F, DeviceDpi / 96F);
        MinimumSize = ScaleWindowSize(new Size(900, 650), scale);
        Size desired = ScaleWindowSize(new Size(1000, 700), scale);
        ClientSize = desired;

        Rectangle workingArea = Screen.FromControl(this).WorkingArea;
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
    }

    private void ShowStatus(string text, StatusKind kind)
    {
        _statusLabel.Text = text;
        switch (kind)
        {
            case StatusKind.Normal:
                _statusLabel.BackColor = AppTheme.SurfaceMuted;
                _statusLabel.ForeColor = AppTheme.TextMuted;
                break;
            case StatusKind.Warning:
                _statusLabel.BackColor = AppTheme.WarningSoft;
                _statusLabel.ForeColor = AppTheme.Warning;
                break;
            case StatusKind.Error:
                _statusLabel.BackColor = AppTheme.ErrorSoft;
                _statusLabel.ForeColor = AppTheme.Error;
                break;
        }
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
