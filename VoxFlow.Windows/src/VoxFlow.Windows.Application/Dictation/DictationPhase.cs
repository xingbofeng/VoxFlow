namespace VoxFlow.Windows.Application.Dictation;

public enum DictationPhase
{
    Idle,
    Preparing,
    Recording,
    WaitingForFinal,
    Processing,
    Injecting,
    Completed,
    Failed,
}
