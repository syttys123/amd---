using System.Globalization;

namespace AmdMobilePower.Gui.Ui;

internal sealed class NumericEntry : TextBox
{
    private int _minimum;
    private int _maximum = 100;
    private int _value;
    private bool _updatingText;

    public NumericEntry()
    {
        BorderStyle = BorderStyle.FixedSingle;
        MaxLength = 3;
        ShortcutsEnabled = false;
        TextAlign = HorizontalAlignment.Right;
    }

    public event EventHandler? ValueChanged;

    public int Minimum
    {
        get => _minimum;
        set
        {
            _minimum = value;
            if (_value < _minimum)
            {
                Value = _minimum;
            }
        }
    }

    public int Maximum
    {
        get => _maximum;
        set
        {
            _maximum = value;
            if (_value > _maximum)
            {
                Value = _maximum;
            }
        }
    }

    public int Value
    {
        get => _value;
        set
        {
            int normalized = Math.Clamp(value, _minimum, _maximum);
            if (_value == normalized && Text.Length > 0)
            {
                return;
            }

            _value = normalized;
            SetText(normalized.ToString(CultureInfo.CurrentCulture));
            ValueChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    protected override void OnKeyPress(KeyPressEventArgs eventArgs)
    {
        if (!char.IsControl(eventArgs.KeyChar) && !char.IsDigit(eventArgs.KeyChar))
        {
            eventArgs.Handled = true;
        }
        base.OnKeyPress(eventArgs);
    }

    protected override void OnTextChanged(EventArgs eventArgs)
    {
        base.OnTextChanged(eventArgs);
        if (_updatingText || Text.Length == 0)
        {
            return;
        }

        if (!int.TryParse(Text, NumberStyles.None, CultureInfo.CurrentCulture, out int parsed) ||
            parsed < _minimum ||
            parsed > _maximum)
        {
            return;
        }

        if (_value == parsed)
        {
            return;
        }

        _value = parsed;
        ValueChanged?.Invoke(this, EventArgs.Empty);
    }

    protected override void OnLeave(EventArgs eventArgs)
    {
        base.OnLeave(eventArgs);
        Value = _value;
    }

    private void SetText(string text)
    {
        _updatingText = true;
        try
        {
            Text = text;
        }
        finally
        {
            _updatingText = false;
        }
    }
}
