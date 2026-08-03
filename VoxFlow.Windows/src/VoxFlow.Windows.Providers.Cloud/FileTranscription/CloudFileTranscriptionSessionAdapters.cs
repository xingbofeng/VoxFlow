using VoxFlow.Windows.Application.Credentials;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.Common;

namespace VoxFlow.Windows.Providers.Cloud.Tencent
{
    public sealed class TencentFileTranscriptionSessionAdapter
        : IFileTranscriptionProviderSessionAdapter
    {
        private readonly Func<CancellationToken, Task<TencentAsrCredentials?>> credentialReader;
        private readonly ICloudWebSocketFactory socketFactory;

        public TencentFileTranscriptionSessionAdapter(
            TencentAsrSettingsService settings,
            ICloudWebSocketFactory socketFactory)
            : this((settings ?? throw new ArgumentNullException(nameof(settings))).RevealAsync,
                socketFactory)
        {
        }

        public TencentFileTranscriptionSessionAdapter(
            Func<CancellationToken, Task<TencentAsrCredentials?>> credentialReader,
            ICloudWebSocketFactory socketFactory)
        {
            this.credentialReader = credentialReader
                ?? throw new ArgumentNullException(nameof(credentialReader));
            this.socketFactory = socketFactory
                ?? throw new ArgumentNullException(nameof(socketFactory));
        }

        public AsrProviderId Provider => AsrProviderId.TencentCloud;

        public async ValueTask<IDictationAsrSession> CreateSessionAsync(
            RecognitionLanguage language,
            Guid generation,
            CancellationToken cancellationToken)
        {
            ValidateLanguage(language);
            var credentials = await ReadCredentialsAsync(
                credentialReader,
                Provider,
                cancellationToken).ConfigureAwait(false);
            return new TencentAsrSession(
                credentials,
                TencentAsrOptions.Default,
                generation.ToString("N"),
                new TencentSignedUrlBuilder(),
                socketFactory.Create());
        }

        private static void ValidateLanguage(RecognitionLanguage language)
        {
            if (!Enum.IsDefined(language))
            {
                throw new ArgumentOutOfRangeException(nameof(language));
            }
        }

        private static async Task<T> ReadCredentialsAsync<T>(
            Func<CancellationToken, Task<T?>> reader,
            AsrProviderId provider,
            CancellationToken cancellationToken) where T : class
        {
            try
            {
                return await reader(cancellationToken).ConfigureAwait(false)
                    ?? throw new FileTranscriptionProviderUnavailableException(provider);
            }
            catch (CredentialUnavailableException)
            {
                throw new FileTranscriptionProviderUnavailableException(provider);
            }
        }
    }
}

namespace VoxFlow.Windows.Providers.Cloud.Aliyun
{
    public sealed class AliyunFileTranscriptionSessionAdapter
        : IFileTranscriptionProviderSessionAdapter
    {
        private readonly Func<CancellationToken, Task<string?>> credentialReader;
        private readonly ICloudWebSocketFactory socketFactory;

        public AliyunFileTranscriptionSessionAdapter(
            AliyunAsrSettingsService settings,
            ICloudWebSocketFactory socketFactory)
            : this((settings ?? throw new ArgumentNullException(nameof(settings))).RevealApiKeyAsync,
                socketFactory)
        {
        }

        public AliyunFileTranscriptionSessionAdapter(
            Func<CancellationToken, Task<string?>> credentialReader,
            ICloudWebSocketFactory socketFactory)
        {
            this.credentialReader = credentialReader
                ?? throw new ArgumentNullException(nameof(credentialReader));
            this.socketFactory = socketFactory
                ?? throw new ArgumentNullException(nameof(socketFactory));
        }

        public AsrProviderId Provider => AsrProviderId.AliyunDashScope;

        public async ValueTask<IDictationAsrSession> CreateSessionAsync(
            RecognitionLanguage language,
            Guid generation,
            CancellationToken cancellationToken)
        {
            ValidateLanguage(language);
            string? apiKey;
            try
            {
                apiKey = await credentialReader(cancellationToken).ConfigureAwait(false);
            }
            catch (CredentialUnavailableException)
            {
                throw new FileTranscriptionProviderUnavailableException(Provider);
            }
            if (string.IsNullOrWhiteSpace(apiKey))
            {
                throw new FileTranscriptionProviderUnavailableException(Provider);
            }

            return new AliyunRealtimeAsrSession(
                apiKey,
                socketFactory,
                () => generation);
        }

        private static void ValidateLanguage(RecognitionLanguage language)
        {
            if (!Enum.IsDefined(language))
            {
                throw new ArgumentOutOfRangeException(nameof(language));
            }
        }
    }
}

namespace VoxFlow.Windows.Providers.Cloud.Volcengine
{
    public sealed class VolcengineFileTranscriptionSessionAdapter
        : IFileTranscriptionProviderSessionAdapter
    {
        private readonly Func<CancellationToken, Task<VolcengineAsrCredentials?>> credentialReader;
        private readonly ICloudWebSocketFactory socketFactory;

        public VolcengineFileTranscriptionSessionAdapter(
            VolcengineAsrSettingsService settings,
            ICloudWebSocketFactory socketFactory)
            : this((settings ?? throw new ArgumentNullException(nameof(settings))).RevealAsync,
                socketFactory)
        {
        }

        public VolcengineFileTranscriptionSessionAdapter(
            Func<CancellationToken, Task<VolcengineAsrCredentials?>> credentialReader,
            ICloudWebSocketFactory socketFactory)
        {
            this.credentialReader = credentialReader
                ?? throw new ArgumentNullException(nameof(credentialReader));
            this.socketFactory = socketFactory
                ?? throw new ArgumentNullException(nameof(socketFactory));
        }

        public AsrProviderId Provider => AsrProviderId.Volcengine;

        public async ValueTask<IDictationAsrSession> CreateSessionAsync(
            RecognitionLanguage language,
            Guid generation,
            CancellationToken cancellationToken)
        {
            ValidateLanguage(language);
            VolcengineAsrCredentials? credentials;
            try
            {
                credentials = await credentialReader(cancellationToken).ConfigureAwait(false);
            }
            catch (CredentialUnavailableException)
            {
                throw new FileTranscriptionProviderUnavailableException(Provider);
            }
            if (credentials is null)
            {
                throw new FileTranscriptionProviderUnavailableException(Provider);
            }

            return new VolcengineRealtimeAsrSession(
                credentials,
                socketFactory,
                () => generation.ToString("N"));
        }

        private static void ValidateLanguage(RecognitionLanguage language)
        {
            if (!Enum.IsDefined(language))
            {
                throw new ArgumentOutOfRangeException(nameof(language));
            }
        }
    }
}
