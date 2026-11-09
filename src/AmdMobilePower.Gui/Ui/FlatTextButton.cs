namespace AmdMobilePower.Gui.Ui;

internal sealed class FlatTextButton : Button
{
    private bool _hovered;
    private bool _pressed;

    public FlatTextButton()
    {
        FlatStyle = FlatStyle.Flat;
        UseVisualStyleBackColor = false;
        SetStyle(ControlStyles.UserPaint, true);
    }

    protected override void OnPaint(PaintEventArgs eventArgs)
    {
        Color background = !Enabled
            ? BackColor
            : _pressed
                ? FlatAppearance.MouseDownBackColor
                : _hovered
                    ? FlatAppearance.MouseOverBackColor
                    : BackColor;
        using SolidBrush backgroundBrush = new(background);
        eventArgs.Graphics.FillRectangle(backgroundBrush, ClientRectangle);

        if (FlatAppearance.BorderSize > 0)
        {
            using Pen border = new(FlatAppearance.BorderColor);
            Rectangle bounds = new(
                0,
                0,
                Math.Max(0, Width - 1),
                Math.Max(0, Height - 1));
            eventArgs.Graphics.DrawRectangle(border, bounds);
        }

        TextRenderer.DrawText(
            eventArgs.Graphics,
            Text,
            Font,
            ClientRectangle,
            ForeColor,
            TextFormatFlags.HorizontalCenter |
            TextFormatFlags.VerticalCenter |
            TextFormatFlags.SingleLine |
            TextFormatFlags.EndEllipsis);

        if (Focused && ShowFocusCues)
        {
            Rectangle focusBounds = ClientRectangle;
            focusBounds.Inflate(-2, -2);
            using Pen focusPen = new(ForeColor, 2)
            {
                Alignment = System.Drawing.Drawing2D.PenAlignment.Inset
            };
            eventArgs.Graphics.DrawRectangle(focusPen, focusBounds);
        }
    }

    protected override void OnGotFocus(EventArgs eventArgs)
    {
        base.OnGotFocus(eventArgs);
        Invalidate();
    }

    protected override void OnLostFocus(EventArgs eventArgs)
    {
        base.OnLostFocus(eventArgs);
        Invalidate();
    }

    protected override void OnMouseEnter(EventArgs eventArgs)
    {
        base.OnMouseEnter(eventArgs);
        _hovered = true;
        Invalidate();
    }

    protected override void OnMouseLeave(EventArgs eventArgs)
    {
        base.OnMouseLeave(eventArgs);
        _hovered = false;
        _pressed = false;
        Invalidate();
    }

    protected override void OnMouseDown(MouseEventArgs eventArgs)
    {
        base.OnMouseDown(eventArgs);
        if (eventArgs.Button == MouseButtons.Left)
        {
            _pressed = true;
            Invalidate();
        }
    }

    protected override void OnMouseUp(MouseEventArgs eventArgs)
    {
        base.OnMouseUp(eventArgs);
        if (eventArgs.Button == MouseButtons.Left)
        {
            _pressed = false;
            Invalidate();
        }
    }

    protected override void OnEnabledChanged(EventArgs eventArgs)
    {
        base.OnEnabledChanged(eventArgs);
        if (!Enabled)
        {
            _hovered = false;
            _pressed = false;
        }
        Invalidate();
    }
}
