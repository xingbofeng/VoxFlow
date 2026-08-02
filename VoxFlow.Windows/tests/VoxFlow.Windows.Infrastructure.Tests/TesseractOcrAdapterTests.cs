using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using VoxFlow.Windows.Infrastructure.Ocr;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests;

public sealed class TesseractOcrAdapterTests
{
    [Fact]
    public void Process_start_info_uses_only_an_argument_list_and_redirects_stderr_without_exposing_it()
    {
        var request = new TesseractOcrProcessRequest(
            @"C:\Program Files\VoxFlow\runtime\ocr\tesseract.exe",
            @"C:\Users\Fixture\AppData\Local\VoxFlow\AgentRuntime\sessions\task\screenshots\ocr.png",
            @"C:\Program Files\VoxFlow\runtime\ocr\tessdata",
            "chi_sim+eng");

        var startInfo = TesseractOcrProcessRunner.CreateStartInfo(request);

        Assert.False(startInfo.UseShellExecute);
        Assert.True(startInfo.CreateNoWindow);
        Assert.True(startInfo.RedirectStandardOutput);
        Assert.True(startInfo.RedirectStandardError);
        Assert.Empty(startInfo.Arguments);
        Assert.Equal(new[]
        {
            request.ScreenshotPath, "stdout", "-l", "chi_sim+eng",
            "--tessdata-dir", request.TessdataPath, "--psm", "3",
        }, startInfo.ArgumentList);
    }

    [Fact]
    public async Task Successful_ocr_returns_only_trimmed_stdout_and_uses_current_language_plus_english()
    {
        using var directory = new TemporaryDirectory();
        var screenshot = Path.Combine(directory.Path, "ocr.png");
        File.WriteAllBytes(screenshot, [1]);
        var process = new FakeProcess(new(0, "  OCR output  \r\n"));
        var adapter = CreateAdapter(process);

        var result = await adapter.RecognizeAsync(screenshot, "ja-JP", CancellationToken.None);

        Assert.Equal(TesseractOcrStatus.Succeeded, result.Status);
        Assert.Equal("OCR output", result.Text);
        Assert.Equal("jpn+eng", process.Request?.Languages);
        Assert.DoesNotContain("stderr", result.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Timeout_and_caller_cancellation_are_distinguished_without_returning_process_diagnostics()
    {
        using var directory = new TemporaryDirectory();
        var screenshot = Path.Combine(directory.Path, "ocr.png");
        File.WriteAllBytes(screenshot, [1]);
        var timeoutAdapter = CreateAdapter(new WaitingProcess(), TimeSpan.FromMilliseconds(30));

        var timeout = await timeoutAdapter.RecognizeAsync(screenshot, "en", CancellationToken.None);
        Assert.Equal(TesseractOcrStatus.TimedOut, timeout.Status);

        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            CreateAdapter(new WaitingProcess()).RecognizeAsync(screenshot, "en", cancellation.Token));
    }

    [Fact]
    public async Task Unavailable_runtime_never_starts_a_process_or_uses_PATH()
    {
        using var directory = new TemporaryDirectory();
        var screenshot = Path.Combine(directory.Path, "ocr.png");
        File.WriteAllBytes(screenshot, [1]);
        var process = new FakeProcess(new(0, "must not run"));
        var adapter = new TesseractOcrAdapter(
            new TesseractRuntimeLocator(directory.Path),
            new FixedVerifier(new(false, TesseractRuntimeVerificationError.ManifestInvalid)),
            process);

        var result = await adapter.RecognizeAsync(screenshot, "en", CancellationToken.None);

        Assert.Equal(TesseractOcrStatus.RuntimeUnavailable, result.Status);
        Assert.Null(process.Request);
    }

    [Fact]
    public async Task Process_runner_normal_cancellation_terminates_job_and_drains_without_exposing_stderr()
    {
        var process = new ControlledProcess(stderr: "sensitive OCR diagnostics");
        var job = new ControlledJob(process) { ExitOnTerminate = true };
        var runner = CreateProcessRunner(process, job);
        using var cancellation = new CancellationTokenSource();

        var run = runner.RunAsync(ProcessRequest(), cancellation.Token);
        Assert.True(process.Started.Wait(TimeSpan.FromSeconds(1)));
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => run);

        Assert.Equal(1, job.TerminateCount);
        Assert.Equal(1, job.DisposeCount);
        Assert.Equal(0, process.KillCount);
        Assert.True(process.WaitForExitCount >= 2);
        Assert.True(process.DisposeCount >= 1);
    }

    [Fact]
    public async Task Process_runner_kill_failure_preserves_cancellation_and_stays_bounded()
    {
        var process = new ControlledProcess
        {
            KillException = new Win32Exception(5, "access denied"),
        };
        var job = new ControlledJob(process);
        var runner = CreateProcessRunner(process, job, TimeSpan.FromMilliseconds(30));
        using var cancellation = new CancellationTokenSource();

        var run = runner.RunAsync(ProcessRequest(), cancellation.Token);
        Assert.True(process.Started.Wait(TimeSpan.FromSeconds(1)));
        var stopwatch = Stopwatch.StartNew();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => run);

        // Bound must stay far below an unbounded hang, but CI runners under load
        // can take longer than a tight local 500ms threshold.
        Assert.True(
            stopwatch.Elapsed < TimeSpan.FromSeconds(2),
            stopwatch.Elapsed.ToString());
        Assert.Equal(1, process.KillCount);
        Assert.Equal(1, job.DisposeCount);
        Assert.True(process.DisposeCount >= 1);
    }

    [Fact]
    public async Task Process_runner_never_waits_unbounded_when_terminated_process_never_reports_exit()
    {
        var process = new ControlledProcess
        {
            ExitOnKill = false,
            IgnoreCleanupCancellation = true,
        };
        var job = new ControlledJob(process);
        var runner = CreateProcessRunner(process, job, TimeSpan.FromMilliseconds(30));
        using var cancellation = new CancellationTokenSource();

        var run = runner.RunAsync(ProcessRequest(), cancellation.Token);
        Assert.True(process.Started.Wait(TimeSpan.FromSeconds(1)));
        var stopwatch = Stopwatch.StartNew();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => run);

        Assert.True(
            stopwatch.Elapsed < TimeSpan.FromSeconds(2),
            stopwatch.Elapsed.ToString());
        Assert.Equal(1, process.KillCount);
        Assert.True(process.WaitForExitCount >= 2);
        Assert.True(process.DisposeCount >= 1);
    }

    [Fact]
    public async Task Process_runner_job_assignment_failure_retires_the_started_process_without_hanging()
    {
        var process = new ControlledProcess { ExitOnKill = true };
        var jobFactory = new ThrowingJobFactory(new Win32Exception(5, "job assignment failed"));
        var runner = new TesseractOcrProcessRunner(
            new ControlledProcessFactory(process),
            jobFactory,
            TimeSpan.FromMilliseconds(30));

        await Assert.ThrowsAsync<Win32Exception>(() =>
            runner.RunAsync(ProcessRequest(), CancellationToken.None));

        Assert.Equal(1, process.KillCount);
        Assert.True(process.DisposeCount >= 1);
    }

    [Fact]
    public async Task Explicit_live_smoke_job_close_terminates_a_real_process_tree()
    {
        if (!string.Equals(
                Environment.GetEnvironmentVariable("VOICEINPUT_TEST_WINDOWS_TESSERACT_JOB"),
                "1",
                StringComparison.Ordinal))
        {
            return;
        }

        var commandInterpreter = Environment.GetEnvironmentVariable("ComSpec")
            ?? Path.Combine(Environment.SystemDirectory, "cmd.exe");
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = commandInterpreter,
                UseShellExecute = false,
                CreateNoWindow = true,
            },
        };
        process.StartInfo.ArgumentList.Add("/d");
        process.StartInfo.ArgumentList.Add("/c");
        process.StartInfo.ArgumentList.Add("ping.exe -t 127.0.0.1 >nul");
        Assert.True(process.Start());
        WindowsTesseractProcessJob? job = null;
        try
        {
            job = WindowsTesseractProcessJob.CreateAndAssign(process.Handle);
            job.Dispose();
            await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(3));
            Assert.True(process.HasExited);
        }
        finally
        {
            job?.Dispose();
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
    }

    private static TesseractOcrAdapter CreateAdapter(
        ITesseractOcrProcessRunner process,
        TimeSpan? timeout = null) => new(
            new TesseractRuntimeLocator(@"C:\Program Files\VoxFlow"),
            new FixedVerifier(new(
                true,
                null,
                ExecutablePath: @"C:\Program Files\VoxFlow\runtime\ocr\tesseract.exe",
                TessdataPath: @"C:\Program Files\VoxFlow\runtime\ocr\tessdata")),
            process,
            timeout);

    private static TesseractOcrProcessRunner CreateProcessRunner(
        ControlledProcess process,
        ControlledJob job,
        TimeSpan? terminationGracePeriod = null) => new(
            new ControlledProcessFactory(process),
            new ControlledJobFactory(job),
            terminationGracePeriod ?? TimeSpan.FromMilliseconds(100));

    private static TesseractOcrProcessRequest ProcessRequest() => new(
        @"C:\Program Files\VoxFlow\runtime\ocr\tesseract.exe",
        @"C:\Users\Fixture\AppData\Local\VoxFlow\ocr.png",
        @"C:\Program Files\VoxFlow\runtime\ocr\tessdata",
        "eng");

    private sealed class FixedVerifier(TesseractRuntimeVerificationResult result)
        : ITesseractRuntimeVerifier
    {
        public TesseractRuntimeVerificationResult Verify(string runtimeDirectory) => result;
    }

    private sealed class FakeProcess(TesseractOcrProcessResult result)
        : ITesseractOcrProcessRunner
    {
        public TesseractOcrProcessRequest? Request { get; private set; }

        public Task<TesseractOcrProcessResult> RunAsync(
            TesseractOcrProcessRequest request,
            CancellationToken cancellationToken)
        {
            Request = request;
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(result);
        }
    }

    private sealed class WaitingProcess : ITesseractOcrProcessRunner
    {
        public async Task<TesseractOcrProcessResult> RunAsync(
            TesseractOcrProcessRequest request,
            CancellationToken cancellationToken)
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            throw new InvalidOperationException("The cancellation test process unexpectedly completed.");
        }
    }

    private sealed class ControlledProcessFactory(ControlledProcess process)
        : ITesseractProcessFactory
    {
        public ITesseractProcess Create(ProcessStartInfo startInfo)
        {
            process.StartInfo = startInfo;
            return process;
        }
    }

    private sealed class ControlledJobFactory(ControlledJob job)
        : ITesseractProcessJobFactory
    {
        public ITesseractProcessJob CreateAndAssign(nint processHandle)
        {
            Assert.Equal(new nint(42), processHandle);
            return job;
        }
    }

    private sealed class ThrowingJobFactory(Exception exception)
        : ITesseractProcessJobFactory
    {
        public ITesseractProcessJob CreateAndAssign(nint processHandle) => throw exception;
    }

    private sealed class ControlledJob(ControlledProcess process) : ITesseractProcessJob
    {
        private int disposed;

        public bool ExitOnTerminate { get; init; }

        public int TerminateCount { get; private set; }

        public int DisposeCount => Volatile.Read(ref disposed);

        public bool TryTerminate()
        {
            TerminateCount++;
            if (ExitOnTerminate)
            {
                process.SignalExit();
            }
            return ExitOnTerminate;
        }

        public void Dispose() => Interlocked.Increment(ref disposed);
    }

    private sealed class ControlledProcess : ITesseractProcess
    {
        private readonly TaskCompletionSource exit = new(
            TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly StreamReader standardOutput;
        private readonly StreamReader standardError;
        private int disposed;
        private int killCount;
        private int waitForExitCount;

        public ControlledProcess(string stdout = "", string stderr = "")
        {
            standardOutput = Reader(stdout);
            standardError = Reader(stderr);
        }

        public ManualResetEventSlim Started { get; } = new(initialState: false);

        public ProcessStartInfo? StartInfo { get; set; }

        public Exception? KillException { get; init; }

        public bool ExitOnKill { get; init; } = true;

        public bool IgnoreCleanupCancellation { get; init; }

        public int DisposeCount => Volatile.Read(ref disposed);

        public int KillCount => Volatile.Read(ref killCount);

        public int WaitForExitCount => Volatile.Read(ref waitForExitCount);

        public nint Handle => new(42);

        public bool HasExited => exit.Task.IsCompleted;

        public int ExitCode => 0;

        public StreamReader StandardOutput => standardOutput;

        public StreamReader StandardError => standardError;

        public bool Start()
        {
            Started.Set();
            return true;
        }

        public Task WaitForExitAsync(CancellationToken cancellationToken)
        {
            var call = Interlocked.Increment(ref waitForExitCount);
            return call > 1 && IgnoreCleanupCancellation
                ? exit.Task
                : exit.Task.WaitAsync(cancellationToken);
        }

        public void Kill(bool entireProcessTree)
        {
            Assert.True(entireProcessTree);
            Interlocked.Increment(ref killCount);
            if (KillException is not null)
            {
                throw KillException;
            }
            if (ExitOnKill)
            {
                SignalExit();
            }
        }

        public void SignalExit() => exit.TrySetResult();

        public void Dispose()
        {
            if (Interlocked.Increment(ref disposed) != 1)
            {
                return;
            }
            standardOutput.Dispose();
            standardError.Dispose();
            SignalExit();
        }

        private static StreamReader Reader(string text) => new(
            new MemoryStream(Encoding.UTF8.GetBytes(text)),
            Encoding.UTF8,
            detectEncodingFromByteOrderMarks: false,
            leaveOpen: false);
    }
}
