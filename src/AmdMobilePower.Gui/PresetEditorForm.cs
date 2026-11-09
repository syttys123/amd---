using AmdMobilePower.Gui.Ui;

namespace AmdMobilePower.Gui;

internal sealed class PresetEditorForm : Form
{
    private readonly NumericUpDown[] _inputs;

    public PresetEditorForm(IReadOnlyList<int> presets, int minimumWatts, int maximumWatts)
    {
        Text = "编辑快速预设";
        ClientSize = new Size(376, 284);
        BackColor = AppTheme.Background;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.CenterParent;
        Font = AppTheme.Body;
        Padding = new Padding(22);

        TableLayoutPanel layout = new()
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 5,
            BackColor = Color.Transparent
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 54));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 46));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
        Controls.Add(layout);

        Label heading = AppTheme.CreateLabel(
            "三个按钮的目标功耗",
            AppTheme.Heading,
            AppTheme.Text);
        heading.Dock = DockStyle.Fill;
        heading.AutoEllipsis = false;
        heading.Margin = Padding.Empty;
        layout.SetColumnSpan(heading, 2);
        layout.Controls.Add(heading, 0, 0);

        _inputs = new NumericUpDown[3];
        for (int index = 0; index < _inputs.Length; index++)
        {
            Label label = AppTheme.CreateLabel(
                $"按钮 {index + 1}",
                AppTheme.Body,
                AppTheme.TextMuted);
            label.Margin = new Padding(0, 8, 8, 8);
            layout.Controls.Add(label, 0, index + 1);

            NumericUpDown input = new()
            {
                Minimum = minimumWatts,
                Maximum = maximumWatts,
                Value = Math.Clamp(presets[index], minimumWatts, maximumWatts),
                Dock = DockStyle.Fill,
                Margin = new Padding(0, 6, 0, 6)
            };
            AppTheme.StyleNumberInput(input);
            input.Font = new Font("Microsoft YaHei UI", 10F, FontStyle.Bold);
            layout.Controls.Add(input, 1, index + 1);
            _inputs[index] = input;
        }

        FlowLayoutPanel actions = new()
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            WrapContents = false,
            BackColor = Color.Transparent,
            Padding = new Padding(0, 4, 0, 0)
        };
        layout.SetColumnSpan(actions, 2);
        layout.Controls.Add(actions, 0, 4);

        Button save = AppTheme.CreateButton("保存", primary: true, width: 104, height: 36);
        save.Click += delegate
        {
            DialogResult = DialogResult.OK;
            Close();
        };
        Button cancel = AppTheme.CreateButton("取消", width: 104, height: 36);
        cancel.Click += delegate
        {
            DialogResult = DialogResult.Cancel;
            Close();
        };
        actions.Controls.Add(save);
        actions.Controls.Add(cancel);
        AcceptButton = save;
        CancelButton = cancel;
    }

    public int[] Presets => _inputs.Select(input => (int)input.Value).ToArray();
}
