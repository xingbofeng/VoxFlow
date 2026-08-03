using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using System.Reflection;

namespace VoxFlow.Windows.Application.Tests;

public sealed class DictationStateMachineTests
{
    [Fact]
    public void Normal_dictation_follows_the_required_phase_sequence()
    {
        var machine = new DictationStateMachine();
        var generation = Guid.NewGuid();
        List<DictationPhase> observed = [machine.Snapshot.Phase];

        machine.Begin(generation);
        observed.Add(machine.Snapshot.Phase);
        machine.Prepared();
        observed.Add(machine.Snapshot.Phase);
        machine.StopRecording();
        observed.Add(machine.Snapshot.Phase);
        Assert.True(machine.TryAcceptFinal(generation, "authoritative ASR text"));
        observed.Add(machine.Snapshot.Phase);
        Assert.True(machine.TryProcessingCompleted(generation, "processed text"));
        observed.Add(machine.Snapshot.Phase);
        Assert.True(machine.TryOutputCompleted(
            generation,
            new OutputResult(OutputResultKind.Inserted)));
        observed.Add(machine.Snapshot.Phase);

        Assert.Equal(
            [
                DictationPhase.Idle,
                DictationPhase.Preparing,
                DictationPhase.Recording,
                DictationPhase.WaitingForFinal,
                DictationPhase.Processing,
                DictationPhase.Injecting,
                DictationPhase.Completed,
            ],
            observed);
        Assert.Equal(generation, machine.Snapshot.Generation);
        Assert.Equal("authoritative ASR text", machine.Snapshot.AuthoritativeText);
        Assert.Equal("processed text", machine.Snapshot.OutputText);
        Assert.Equal(OutputResultKind.Inserted, machine.Snapshot.Output!.Kind);

        machine.Reset();

        Assert.Equal(DictationSnapshot.Idle, machine.Snapshot);
    }

    [Theory]
    [InlineData(DictationPhase.Preparing)]
    [InlineData(DictationPhase.Recording)]
    [InlineData(DictationPhase.WaitingForFinal)]
    [InlineData(DictationPhase.Processing)]
    [InlineData(DictationPhase.Injecting)]
    public void Cancel_from_any_active_phase_returns_to_clean_idle(
        DictationPhase activePhase)
    {
        var machine = CreateAt(activePhase);

        machine.Cancel();

        Assert.Equal(DictationSnapshot.Idle, machine.Snapshot);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Empty_final_enters_an_observable_failure(string finalText)
    {
        var machine = CreateAt(DictationPhase.WaitingForFinal);
        var generation = machine.Snapshot.Generation!.Value;

        Assert.True(machine.TryAcceptFinal(generation, finalText));

        Assert.Equal(DictationPhase.Failed, machine.Snapshot.Phase);
        Assert.Equal(VoxFlowErrorCode.EmptyFinal, machine.Snapshot.Error!.Code);
        Assert.NotNull(machine.Snapshot.Generation);

        machine.Reset();
        Assert.Equal(DictationPhase.Idle, machine.Snapshot.Phase);
    }

    [Fact]
    public void Final_timeout_enters_an_observable_failure()
    {
        var machine = CreateAt(DictationPhase.WaitingForFinal);
        var generation = machine.Snapshot.Generation!.Value;

        Assert.True(machine.TryFinalTimedOut(generation));

        Assert.Equal(DictationPhase.Failed, machine.Snapshot.Phase);
        Assert.Equal(VoxFlowErrorCode.FinalTimeout, machine.Snapshot.Error!.Code);
    }

    [Fact]
    public void Authoritative_final_is_accepted_only_once()
    {
        var machine = CreateAt(DictationPhase.WaitingForFinal);
        var generation = machine.Snapshot.Generation!.Value;
        Assert.True(machine.TryAcceptFinal(generation, "first final"));
        var accepted = machine.Snapshot;

        Assert.False(machine.TryAcceptFinal(generation, "late second final"));

        Assert.Equal(accepted, machine.Snapshot);
        Assert.Equal("first final", machine.Snapshot.AuthoritativeText);
    }

    [Fact]
    public void Illegal_transition_throws_without_mutating_the_snapshot()
    {
        var machine = new DictationStateMachine();
        var before = machine.Snapshot;

        var exception = Assert.Throws<InvalidDictationTransitionException>(machine.Prepared);

        Assert.Equal(DictationPhase.Idle, exception.Current);
        Assert.Equal(DictationPhase.Recording, exception.Requested);
        Assert.Equal(before, machine.Snapshot);
    }

    [Fact]
    public void Begin_rejects_an_empty_generation_and_cannot_replace_an_active_session()
    {
        var machine = new DictationStateMachine();

        Assert.Throws<ArgumentException>(() => machine.Begin(Guid.Empty));

        machine.Begin(Guid.NewGuid());
        var active = machine.Snapshot;

        Assert.Throws<InvalidDictationTransitionException>(() =>
            machine.Begin(Guid.NewGuid()));
        Assert.Equal(active, machine.Snapshot);
    }

    [Fact]
    public void Provider_callbacks_arriving_after_cancel_are_dropped()
    {
        var machine = CreateAt(DictationPhase.WaitingForFinal);
        var generation = machine.Snapshot.Generation!.Value;

        machine.Cancel();

        Assert.False(machine.TryAcceptFinal(generation, "late final"));
        Assert.False(machine.TryFail(
            generation,
            new VoxFlowError(VoxFlowErrorCode.ProviderFailure)));
        Assert.False(machine.TryFinalTimedOut(generation));
        Assert.Same(DictationSnapshot.Idle, machine.Snapshot);
    }

    [Fact]
    public void Stale_provider_callbacks_cannot_mutate_a_new_session()
    {
        var machine = CreateAt(DictationPhase.WaitingForFinal);
        var staleGeneration = machine.Snapshot.Generation!.Value;
        machine.Cancel();

        var currentGeneration = Guid.NewGuid();
        machine.Begin(currentGeneration);
        machine.Prepared();
        machine.StopRecording();
        var current = machine.Snapshot;

        Assert.False(machine.TryAcceptFinal(staleGeneration, "stale final"));
        Assert.False(machine.TryFail(
            staleGeneration,
            new VoxFlowError(VoxFlowErrorCode.ProviderFailure)));
        Assert.False(machine.TryFinalTimedOut(staleGeneration));
        Assert.Same(current, machine.Snapshot);
    }

    [Fact]
    public void Cancel_racing_with_a_provider_final_has_an_atomic_idle_result()
    {
        for (var iteration = 0; iteration < 500; iteration++)
        {
            var machine = CreateAt(DictationPhase.WaitingForFinal);
            var generation = machine.Snapshot.Generation!.Value;

            Parallel.Invoke(
                machine.Cancel,
                () => machine.TryAcceptFinal(generation, "racing final"));

            Assert.Same(DictationSnapshot.Idle, machine.Snapshot);
            Assert.False(machine.TryAcceptFinal(generation, "late final"));
        }
    }

    [Fact]
    public void Final_winning_the_race_makes_a_late_timeout_a_no_op()
    {
        var machine = CreateAt(DictationPhase.WaitingForFinal);
        var generation = machine.Snapshot.Generation!.Value;

        Assert.True(machine.TryAcceptFinal(generation, "authoritative final"));
        var processing = machine.Snapshot;

        Assert.False(machine.TryFinalTimedOut(generation));
        Assert.Same(processing, machine.Snapshot);
    }

    [Fact]
    public void Old_processing_and_output_completions_cannot_advance_a_new_generation()
    {
        var machine = CreateAt(DictationPhase.Processing);
        var staleGeneration = machine.Snapshot.Generation!.Value;
        machine.Cancel();

        var currentGeneration = Guid.NewGuid();
        MoveToProcessing(machine, currentGeneration);
        var currentProcessing = machine.Snapshot;

        Assert.False(machine.TryProcessingCompleted(staleGeneration, "stale processed text"));
        Assert.Same(currentProcessing, machine.Snapshot);
        Assert.True(machine.TryProcessingCompleted(currentGeneration, "current processed text"));
        var currentInjecting = machine.Snapshot;

        Assert.False(machine.TryOutputCompleted(
            staleGeneration,
            new OutputResult(OutputResultKind.Inserted)));
        Assert.Same(currentInjecting, machine.Snapshot);
        Assert.True(machine.TryOutputCompleted(
            currentGeneration,
            new OutputResult(OutputResultKind.Inserted)));
        Assert.Equal(DictationPhase.Completed, machine.Snapshot.Phase);
    }

    [Fact]
    public void Provider_error_after_authoritative_final_is_dropped()
    {
        var machine = CreateAt(DictationPhase.Processing);
        var generation = machine.Snapshot.Generation!.Value;
        var processing = machine.Snapshot;

        Assert.False(machine.TryFail(
            generation,
            new VoxFlowError(VoxFlowErrorCode.ProviderFailure)));
        Assert.Same(processing, machine.Snapshot);
    }

    [Fact]
    public void Snapshots_cannot_be_constructed_or_mutated_by_external_callers()
    {
        var snapshotType = typeof(DictationSnapshot);

        Assert.Empty(snapshotType.GetConstructors(BindingFlags.Instance | BindingFlags.Public));

        foreach (var propertyName in new[]
                 {
                     nameof(DictationSnapshot.Phase),
                     nameof(DictationSnapshot.Generation),
                     nameof(DictationSnapshot.AuthoritativeText),
                     nameof(DictationSnapshot.OutputText),
                     nameof(DictationSnapshot.Output),
                     nameof(DictationSnapshot.Error),
                 })
        {
            var property = snapshotType.GetProperty(propertyName);
            Assert.NotNull(property);
            Assert.Null(property.SetMethod);
        }
    }

    private static DictationStateMachine CreateAt(DictationPhase phase)
    {
        var machine = new DictationStateMachine();
        machine.Begin(Guid.NewGuid());

        if (phase == DictationPhase.Preparing)
        {
            return machine;
        }

        machine.Prepared();
        if (phase == DictationPhase.Recording)
        {
            return machine;
        }

        machine.StopRecording();
        if (phase == DictationPhase.WaitingForFinal)
        {
            return machine;
        }

        Assert.True(machine.TryAcceptFinal(
            machine.Snapshot.Generation!.Value,
            "authoritative ASR text"));
        if (phase == DictationPhase.Processing)
        {
            return machine;
        }

        Assert.True(machine.TryProcessingCompleted(
            machine.Snapshot.Generation!.Value,
            "processed text"));
        if (phase == DictationPhase.Injecting)
        {
            return machine;
        }

        throw new ArgumentOutOfRangeException(nameof(phase), phase, null);
    }

    private static void MoveToProcessing(
        DictationStateMachine machine,
        Guid generation)
    {
        machine.Begin(generation);
        machine.Prepared();
        machine.StopRecording();
        Assert.True(machine.TryAcceptFinal(generation, "authoritative ASR text"));
    }
}
