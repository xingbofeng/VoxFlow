namespace VoxFlow.Windows.Application.Dictation;

public sealed class InvalidDictationTransitionException : InvalidOperationException
{
    public InvalidDictationTransitionException(
        DictationPhase current,
        DictationPhase requested)
        : base($"Cannot transition dictation from {current} to {requested}.")
    {
        Current = current;
        Requested = requested;
    }

    public DictationPhase Current { get; }

    public DictationPhase Requested { get; }
}
