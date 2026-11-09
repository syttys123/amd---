using System.Drawing.Drawing2D;

namespace AmdMobilePower.Gui.Ui;

internal sealed class CardPanel : Panel
{
    public CardPanel()
    {
        DoubleBuffered = true;
        BackColor = AppTheme.Surface;
        Padding = new Padding(22);
        Resize += delegate { UpdateRegion(); };
    }

    protected override void OnPaint(PaintEventArgs eventArgs)
    {
        base.OnPaint(eventArgs);
        eventArgs.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using GraphicsPath path = CreateRoundedPath(ClientRectangle, 8);
        using Pen border = new(AppTheme.Border, 1);
        eventArgs.Graphics.DrawPath(border, path);
    }

    private void UpdateRegion()
    {
        if (Width <= 0 || Height <= 0)
        {
            return;
        }

        using GraphicsPath path = CreateRoundedPath(ClientRectangle, 8);
        Region? previous = Region;
        Region = new Region(path);
        previous?.Dispose();
    }

    private static GraphicsPath CreateRoundedPath(Rectangle bounds, int radius)
    {
        int diameter = radius * 2;
        Rectangle adjusted = new(bounds.X, bounds.Y, bounds.Width - 1, bounds.Height - 1);
        GraphicsPath path = new();
        path.AddArc(adjusted.X, adjusted.Y, diameter, diameter, 180, 90);
        path.AddArc(adjusted.Right - diameter, adjusted.Y, diameter, diameter, 270, 90);
        path.AddArc(
            adjusted.Right - diameter,
            adjusted.Bottom - diameter,
            diameter,
            diameter,
            0,
            90);
        path.AddArc(adjusted.X, adjusted.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }
}
