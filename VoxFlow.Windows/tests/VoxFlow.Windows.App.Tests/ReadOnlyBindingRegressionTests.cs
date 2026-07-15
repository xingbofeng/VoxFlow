using System.Windows;
using VoxFlow.Windows.App.Settings;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class ReadOnlyBindingRegressionTests
{
    [Fact]
    public async Task OpenAI_card_can_measure_with_a_read_only_base_URL()
    {
        await StaWpfTestHost.RunAsync(_ =>
        {
            var view = new OpenAiSettingsCardView
            {
                DataContext = new ReadOnlyOpenAiCard(),
            };

            view.Measure(new Size(900, 600));
            view.Arrange(new Rect(0, 0, 900, 600));
            view.UpdateLayout();

            Assert.True(view.IsMeasureValid);
            return Task.CompletedTask;
        });
    }

    private sealed class ReadOnlyOpenAiCard
    {
        public string Heading => "OpenAI";
        public string Description => "Settings";
        public string BaseUrl => "https://api.openai.com/v1";
        public string Model { get; set; } = "gpt-4.1-mini";
        public bool Enabled { get; set; }
        public string ApiKeyPresentation => string.Empty;
        public string FeedbackMessage => string.Empty;
    }
}
