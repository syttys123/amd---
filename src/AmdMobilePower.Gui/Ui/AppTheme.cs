namespace AmdMobilePower.Gui.Ui;

internal static class AppTheme
{
    public static readonly Color Background = Color.FromArgb(242, 245, 242);
    public static readonly Color Header = Color.FromArgb(22, 34, 33);
    public static readonly Color HeaderMuted = Color.FromArgb(164, 180, 177);
    public static readonly Color Surface = Color.White;
    public static readonly Color SurfaceMuted = Color.FromArgb(247, 249, 247);
    public static readonly Color Border = Color.FromArgb(216, 224, 219);
    public static readonly Color Text = Color.FromArgb(27, 38, 37);
    public static readonly Color TextMuted = Color.FromArgb(96, 110, 107);
    public static readonly Color Accent = Color.FromArgb(12, 132, 119);
    public static readonly Color AccentHover = Color.FromArgb(9, 110, 99);
    public static readonly Color AccentSoft = Color.FromArgb(226, 245, 241);
    public static readonly Color Battery = Color.FromArgb(195, 112, 28);
    public static readonly Color BatterySoft = Color.FromArgb(255, 246, 232);
    public static readonly Color Warning = Color.FromArgb(180, 83, 9);
    public static readonly Color WarningSoft = Color.FromArgb(255, 247, 237);
    public static readonly Color Error = Color.FromArgb(185, 28, 28);
    public static readonly Color ErrorSoft = Color.FromArgb(254, 242, 242);

    public static readonly Font Body = new("Microsoft YaHei UI", 9F);
    public static readonly Font BodyBold = new("Microsoft YaHei UI", 9F, FontStyle.Bold);
    public static readonly Font Small = new("Microsoft YaHei UI", 8.25F);
    public static readonly Font SmallBold = new("Microsoft YaHei UI", 8.25F, FontStyle.Bold);
    public static readonly Font Heading = new("Microsoft YaHei UI", 12F, FontStyle.Bold);
    public static readonly Font Display = new("Segoe UI Variable Display", 30F, FontStyle.Bold);
    public static readonly Font Title = new("Segoe UI Variable Display", 17F, FontStyle.Bold);

    public static Label CreateLabel(
        string text,
        Font? font = null,
        Color? color = null,
        ContentAlignment alignment = ContentAlignment.MiddleLeft)
    {
        return new Label
        {
            AutoSize = false,
            Text = text,
            Font = font ?? Body,
            ForeColor = color ?? Text,
            TextAlign = alignment,
            BackColor = Color.Transparent,
            UseMnemonic = false,
            AutoEllipsis = true
        };
    }

    public static Button CreateButton(
        string text,
        bool primary = false,
        int width = 120,
        int height = 38)
    {
        Button button = new()
        {
            Text = text,
            Width = width,
            Height = height,
            BackColor = primary ? Accent : Surface,
            ForeColor = primary ? Color.White : Text,
            FlatStyle = FlatStyle.Flat,
            Font = BodyBold,
            Cursor = Cursors.Hand,
            UseVisualStyleBackColor = false,
            TabStop = true
        };
        button.FlatAppearance.BorderSize = primary ? 0 : 1;
        button.FlatAppearance.BorderColor = Border;
        button.FlatAppearance.MouseOverBackColor = primary ? AccentHover : SurfaceMuted;
        button.FlatAppearance.MouseDownBackColor = primary ? AccentHover : Border;
        return button;
    }

    public static void StyleNumberInput(NumericUpDown input)
    {
        input.Font = new Font("Microsoft YaHei UI", 13F, FontStyle.Bold);
        input.ForeColor = Text;
        input.BackColor = Surface;
        input.BorderStyle = BorderStyle.FixedSingle;
        input.TextAlign = HorizontalAlignment.Right;
        input.ThousandsSeparator = false;
        input.Width = 120;
        input.Height = 34;
    }
}
