using System.Drawing.Drawing2D;

namespace AmdMobilePower.Gui.Ui;

internal sealed class PowerUsageBar : Control
{
    private double _value;
    private double _maximum = 60;
    private bool _warning;

    public PowerUsageBar()
    {
        DoubleBuffered = true;
        SetStyle(ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        Height = 10;
    }

    public double Value
    {
        get => _value;
        set
        {
            _value = Math.Max(0, Math.Min(value, _maximum));
            Invalidate();
        }
    }

    public double Maximum
    {
        get => _maximum;
        set
        {
            _maximum = Math.Max(1, value);
            Invalidate();
        }
    }

    public bool Warning
    {
        get => _warning;
        set
        {
            _warning = value;
            Invalidate();
        }
    }

    protected override void OnPaint(PaintEventArgs eventArgs)
    {
        base.OnPaint(eventArgs);
        eventArgs.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle track = new(0, 2, Width - 1, Height - 5);
        using GraphicsPath trackPath = RoundedPath(track, track.Height);
        using SolidBrush trackBrush = new(AppTheme.Border);
        eventArgs.Graphics.FillPath(trackBrush, trackPath);

        double fraction = Math.Clamp(Value / Maximum, 0, 1);
        int fillWidth = (int)Math.Round(track.Width * fraction);
        if (fillWidth <= 0)
        {
            return;
        }

        Rectangle fill = new(track.X, track.Y, fillWidth, track.Height);
        using GraphicsPath fillPath = RoundedPath(fill, fill.Height);
        using SolidBrush fillBrush = new(Warning ? AppTheme.Battery : AppTheme.Accent);
        eventArgs.Graphics.FillPath(fillBrush, fillPath);
    }

    private static GraphicsPath RoundedPath(Rectangle bounds, int radius)
    {
        int diameter = Math.Max(1, radius * 2);
        GraphicsPath path = new();
        path.AddArc(bounds.X, bounds.Y, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Y, diameter, diameter, 270, 90);
        path.AddArc(
            bounds.Right - diameter,
            bounds.Bottom - diameter,
            diameter,
            diameter,
            0,
            90);
        path.AddArc(bounds.X, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }
}
