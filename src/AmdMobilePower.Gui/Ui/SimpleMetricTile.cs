namespace AmdMobilePower.Gui.Ui;

internal sealed class SimpleMetricTile : TableLayoutPanel
{
    private readonly Label _valueLabel;
    private readonly Label _limitLabel;

    public SimpleMetricTile(string title)
    {
        Dock = DockStyle.Fill;
        ColumnCount = 1;
        RowCount = 3;
        BackColor = Color.Transparent;
        Margin = Padding.Empty;
        Padding = new Padding(10, 12, 10, 10);

        RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        RowStyles.Add(new RowStyle(SizeType.Absolute, 26));

        Label titleLabel = AppTheme.CreateLabel(
            title,
            AppTheme.Small,
            AppTheme.TextMuted);
        titleLabel.Dock = DockStyle.Fill;
        titleLabel.Margin = Padding.Empty;
        titleLabel.AutoEllipsis = false;
        Controls.Add(titleLabel, 0, 0);

        _valueLabel = AppTheme.CreateLabel(
            "--",
            AppTheme.Metric,
            AppTheme.Text);
        _valueLabel.Dock = DockStyle.Fill;
        _valueLabel.Margin = Padding.Empty;
        _valueLabel.AutoEllipsis = false;
        Controls.Add(_valueLabel, 0, 1);

        _limitLabel = AppTheme.CreateLabel(
            "上限 --",
            AppTheme.Small,
            AppTheme.TextMuted);
        _limitLabel.Dock = DockStyle.Fill;
        _limitLabel.Margin = Padding.Empty;
        _limitLabel.AutoEllipsis = false;
        Controls.Add(_limitLabel, 0, 2);
    }

    public void SetReading(string value, string limit)
    {
        _valueLabel.Text = value;
        _limitLabel.Text = limit;
    }

    public Label ValueLabel => _valueLabel;

    public Label LimitLabel => _limitLabel;
}
