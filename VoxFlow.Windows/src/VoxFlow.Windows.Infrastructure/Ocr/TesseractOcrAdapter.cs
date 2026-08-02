using System.ComponentModel;
using System.Diagnostics;
using System.Text;

namespace VoxFlow.Windows.Infrastructure.Ocr;

public sealed record TesseractOcrProcessRequest
{
    public TesseractOcrProcessRequest(
        string executablePath,
        string screenshotPath,
        string tessdataPath,
        string languages,
        TesseractOcrOutputFormat outputFormat = TesseractOcrOutputFormat.PlainText)
    {
        if (!Enum.IsDefined(outputFormat))
        {
            throw new ArgumentOutOfRangeException(nameof(outputFormat));
        }
        ExecutablePath = RequireAbsolute(executablePath, nameof(executablePath));
        ScreenshotPath = RequireAbsolute(screenshotPath, nameof(screenshotPath));
        TessdataPath = RequireAbsolute(tessdataPath, nameof(tessdataPath));
        Languages = RequireLanguages(languages);
        OutputFormat = outputFormat;
    }

    public string ExecutablePath { get; }

    public string ScreenshotPath { get; }

    public string TessdataPath { get; }

    public string Languages { get; }

    public TesseractOcrOutputFormat OutputFormat { get; }

    private static string RequireAbsolute(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);
        if (!Path.IsPathFullyQualified(value))
        {
            throw new ArgumentException("OCR paths must be absolute.", parameterName);
        }
        return Path.GetFullPath(value);
    }

    private static string RequireLanguages(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        if (value.Split('+').Any(language =>
                !TesseractRuntimeVerifier.RequiredLanguageModels.ContainsKey(language)))
        {
            throw new ArgumentException("Only bundled OCR languages are allowed.", nameof(value));
        }
        return value;
    }
}

public enum TesseractOcrOutputFormat
{
    PlainText,
    Tsv,
}

public sealed record TesseractOcrProcessResult(int ExitCode, string StandardOutput);

public interface ITesseractOcrProcessRunner
{
    Task<TesseractOcrProcessResult> RunAsync(
        TesseractOcrProcessRequest request,
        CancellationToken cancellationToken);
}

internal interface ITesseractProcess : IDisposable
{
    bool Start();

    nint Handle { get; }

    bool HasExited { get; }

    int ExitCode { get; }

    StreamReader StandardOutput { get; }

    StreamReader StandardError { get; }

    Task WaitForExitAsync(CancellationToken cancellationToken);

    void Kill(bool entireProcessTree);
}

internal interface ITesseractProcessFactory
{
    ITesseractProcess Create(ProcessStartInfo startInfo);
}

internal sealed class SystemTesseractProcessFactory : ITesseractProcessFactory
{
    public static SystemTesseractProcessFactory Instance { get; } = new();

    private SystemTesseractProcessFactory()
    {
    }

    public ITesseractProcess Create(ProcessStartInfo startInfo) => new SystemTesseractProcess(startInfo);

    private sealed class SystemTesseractProcess : ITesseractProcess
    {
        private readonly Process process;

        public SystemTesseractProcess(ProcessStartInfo startInfo)
        {
            process = new Process
            {
                StartInfo = startInfo,
                EnableRaisingEvents = true,
            };
        }

        public nint Handle => process.Handle;

        public bool HasExited => process.HasExited;

        public int ExitCode => process.ExitCode;

        public StreamReader StandardOutput => process.StandardOutput;

        public StreamReader StandardError => process.StandardError;

        public bool Start() => process.Start();

        public Task WaitForExitAsync(CancellationToken cancellationToken) =>
            process.WaitForExitAsync(cancellationToken);

        public void Kill(bool entireProcessTree) => process.Kill(entireProcessTree);

        public void Dispose() => process.Dispose();
    }
}

/// <summary>Runs the hash-verified bundled binary with a fixed argument list.
/// stderr is consumed only to avoid pipe deadlock and is never returned,
/// logged, persisted, or surfaced to the model.</summary>
public sealed class TesseractOcrProcessRunner : ITesseractOcrProcessRunner
{
    private const int OutputCharacterLimit = 100_000;
    internal static readonly TimeSpan DefaultTerminationGracePeriod = TimeSpan.FromSeconds(1);

    private readonly ITesseractProcessFactory processFactory;
    private readonly ITesseractProcessJobFactory jobFactory;
    private readonly TimeSpan terminationGracePeriod;

    public TesseractOcrProcessRunner()
        : this(
            SystemTesseractProcessFactory.Instance,
            WindowsTesseractProcessJobFactory.Instance,
            DefaultTerminationGracePeriod)
    {
    }

    internal TesseractOcrProcessRunner(
        ITesseractProcessFactory processFactory,
        ITesseractProcessJobFactory jobFactory,
        TimeSpan terminationGracePeriod)
    {
        this.processFactory = processFactory ?? throw new ArgumentNullException(nameof(processFactory));
        this.jobFactory = jobFactory ?? throw new ArgumentNullException(nameof(jobFactory));
        if (terminationGracePeriod <= TimeSpan.Zero
            || terminationGracePeriod == Timeout.InfiniteTimeSpan)
        {
            throw new ArgumentOutOfRangeException(nameof(terminationGracePeriod));
        }
        this.terminationGracePeriod = terminationGracePeriod;
    }

    public async Task<TesseractOcrProcessResult> RunAsync(
        TesseractOcrProcessRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();
        var process = processFactory.Create(CreateStartInfo(request));
        ITesseractProcessJob? job = null;
        var processStarted = false;
        var terminationAttempted = false;
        try
        {
            if (!process.Start())
            {
                throw new InvalidOperationException("The controlled OCR process could not be started.");
            }
            processStarted = true;
            job = jobFactory.CreateAndAssign(process.Handle);

            var outputTask = ReadLimitedAsync(process.StandardOutput);
            var discardErrorTask = DrainAsync(process.StandardError);
            try
            {
                await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
                await Task.WhenAll(outputTask, discardErrorTask)
                    .WaitAsync(cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                var terminatingJob = job;
                job = null;
                terminationAttempted = true;
                await TerminateBoundedAsync(
                        process,
                        terminatingJob,
                        outputTask,
                        discardErrorTask)
                    .ConfigureAwait(false);
                throw;
            }

            return new(process.ExitCode, outputTask.Result);
        }
        catch
        {
            if (processStarted && !terminationAttempted)
            {
                var terminatingJob = job;
                job = null;
                terminationAttempted = true;
                await TerminateBoundedAsync(
                        process,
                        terminatingJob,
                        Task.CompletedTask,
                        Task.CompletedTask)
                    .ConfigureAwait(false);
            }
            throw;
        }
        finally
        {
            job?.Dispose();
            process.Dispose();
        }
    }

    internal static ProcessStartInfo CreateStartInfo(TesseractOcrProcessRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        var startInfo = new ProcessStartInfo
        {
            FileName = request.ExecutablePath,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            RedirectStandardInput = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        List<string> arguments =
        [
            request.ScreenshotPath,
            "stdout",
            "-l",
            request.Languages,
            "--tessdata-dir",
            request.TessdataPath,
            "--psm",
            "3",
        ];
        if (request.OutputFormat == TesseractOcrOutputFormat.Tsv)
        {
            arguments.Add("tsv");
        }
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }
        return startInfo;
    }

    private static async Task<string> ReadLimitedAsync(StreamReader reader)
    {
        var output = new StringBuilder(OutputCharacterLimit);
        var buffer = new char[4_096];
        while (true)
        {
            var read = await reader.ReadAsync(buffer).ConfigureAwait(false);
            if (read == 0)
            {
                return output.ToString();
            }
            var remaining = OutputCharacterLimit - output.Length;
            if (remaining > 0)
            {
                output.Append(buffer, 0, Math.Min(read, remaining));
            }
        }
    }

    private static async Task DrainAsync(StreamReader reader)
    {
        var buffer = new char[4_096];
        while (await reader.ReadAsync(buffer).ConfigureAwait(false) != 0)
        {
            // Never retain potentially sensitive OCR runtime diagnostics.
        }
    }

    private async Task TerminateBoundedAsync(
        ITesseractProcess process,
        ITesseractProcessJob? job,
        Task outputTask,
        Task discardErrorTask)
    {
        TryTerminateJob(job);
        TryDisposeJob(job);
        TryKillProcessTree(process);

        using var cleanupCancellation = new CancellationTokenSource(terminationGracePeriod);
        Task exitTask;
        try
        {
            exitTask = process.WaitForExitAsync(cleanupCancellation.Token);
        }
        catch (Exception exception) when (IsExpectedProcessControlFailure(exception))
        {
            return;
        }

        var cleanupTask = Task.WhenAll(exitTask, outputTask, discardErrorTask);
        try
        {
            await cleanupTask
                .WaitAsync(terminationGracePeriod)
                .ConfigureAwait(false);
        }
        catch (Exception exception) when (
            exception is TimeoutException or OperationCanceledException
            || IsExpectedProcessControlFailure(exception))
        {
            // Process.Dispose closes redirected pipe handles. The Job Object has
            // already been closed with KILL_ON_JOB_CLOSE, so this wait is never
            // allowed to extend the public OCR timeout.
            process.Dispose();
            ObserveLateCleanup(cleanupTask);
        }
    }

    private static void TryTerminateJob(ITesseractProcessJob? job)
    {
        if (job is null)
        {
            return;
        }
        try
        {
            _ = job.TryTerminate();
        }
        catch (Exception exception) when (IsExpectedProcessControlFailure(exception))
        {
            // Closing a KILL_ON_JOB_CLOSE handle below remains the primary backstop.
        }
    }

    private static void TryDisposeJob(ITesseractProcessJob? job)
    {
        try
        {
            job?.Dispose();
        }
        catch (Exception exception) when (IsExpectedProcessControlFailure(exception))
        {
            // Process.Kill is the final best-effort fallback.
        }
    }

    private static void TryKillProcessTree(ITesseractProcess process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch (Exception exception) when (IsExpectedProcessControlFailure(exception))
        {
            // Kill(Boolean) is asynchronous and can fail if Windows denies process
            // access or a descendant races exit. The Job Object is the primary owner.
        }
    }

    private static bool IsExpectedProcessControlFailure(Exception exception) => exception is
        InvalidOperationException or
        Win32Exception or
        NotSupportedException or
        AggregateException or
        ObjectDisposedException or
        IOException;

    private static void ObserveLateCleanup(Task cleanupTask)
    {
        _ = cleanupTask.ContinueWith(
            static completed => _ = completed.Exception,
            CancellationToken.None,
            TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
    }
}

public enum TesseractOcrStatus
{
    Succeeded,
    RuntimeUnavailable,
    InputUnavailable,
    Empty,
    TimedOut,
    Failed,
}

public sealed record TesseractOcrResult(TesseractOcrStatus Status, string? Text = null)
{
    public bool Succeeded => Status == TesseractOcrStatus.Succeeded;
}

/// <summary>High-level OCR boundary. It verifies the runtime immediately
/// before every execution and exposes only normalized text or stable safe
/// status codes, never stderr or image bytes.</summary>
public sealed class TesseractOcrAdapter
{
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(20);
    private readonly TesseractRuntimeLocator runtime;
    private readonly ITesseractRuntimeVerifier verifier;
    private readonly ITesseractOcrProcessRunner process;
    private readonly TimeSpan timeout;

    public TesseractOcrAdapter(
        TesseractRuntimeLocator runtime,
        ITesseractRuntimeVerifier verifier,
        ITesseractOcrProcessRunner process,
        TimeSpan? timeout = null)
    {
        this.runtime = runtime ?? throw new ArgumentNullException(nameof(runtime));
        this.verifier = verifier ?? throw new ArgumentNullException(nameof(verifier));
        this.process = process ?? throw new ArgumentNullException(nameof(process));
        this.timeout = timeout ?? DefaultTimeout;
        if (this.timeout <= TimeSpan.Zero || this.timeout == Timeout.InfiniteTimeSpan)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }
    }

    public async Task<TesseractOcrResult> RecognizeAsync(
        string screenshotPath,
        string? currentLanguage,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(screenshotPath);
        cancellationToken.ThrowIfCancellationRequested();
        var verified = verifier.Verify(runtime.RuntimeDirectory);
        if (!verified.IsValid || verified.ExecutablePath is null || verified.TessdataPath is null)
        {
            return new(TesseractOcrStatus.RuntimeUnavailable);
        }
        var path = Path.GetFullPath(screenshotPath);
        if (!File.Exists(path))
        {
            return new(TesseractOcrStatus.InputUnavailable);
        }

        using var timeoutCancellation = new CancellationTokenSource(timeout);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            timeoutCancellation.Token);
        try
        {
            var result = await process.RunAsync(
                new TesseractOcrProcessRequest(
                    verified.ExecutablePath,
                    path,
                    verified.TessdataPath,
                    TesseractLanguageSelector.SelectWithEnglish(currentLanguage)),
                linked.Token).ConfigureAwait(false);
            if (result.ExitCode != 0)
            {
                return new(TesseractOcrStatus.Failed);
            }
            var text = result.StandardOutput.Trim();
            return string.IsNullOrWhiteSpace(text)
                ? new(TesseractOcrStatus.Empty)
                : new(TesseractOcrStatus.Succeeded, text);
        }
        catch (OperationCanceledException) when (timeoutCancellation.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
        {
            return new(TesseractOcrStatus.TimedOut);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            return new(TesseractOcrStatus.Failed);
        }
    }
}
