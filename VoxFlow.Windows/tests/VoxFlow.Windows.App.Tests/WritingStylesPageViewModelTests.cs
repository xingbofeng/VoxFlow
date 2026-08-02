using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.Application.Text;

namespace VoxFlow.Windows.App.Tests;

public sealed class WritingStylesPageViewModelTests
{
    [Fact]
    public async Task Load_exposes_seven_built_ins_and_blocks_deleting_them()
    {
        var store = new MemoryStore(WritingStyleDocument.Default);
        var vm = new WritingStylesPageViewModel(store);

        await vm.LoadAsync();

        Assert.Equal(7, vm.Profiles.Count);
        Assert.All(vm.Profiles, profile => Assert.True(profile.IsBuiltIn));
        Assert.All(vm.Profiles, profile => Assert.False(profile.CanDelete));

        vm.SelectedProfile = vm.Profiles.First();
        await vm.DeleteSelectedAsync();

        Assert.Equal(7, vm.Profiles.Count);
        Assert.Equal(7, (await store.LoadAsync(CancellationToken.None)).Profiles.Count);
    }

    [Fact]
    public async Task Save_persists_per_style_ai_match_and_preview_is_not_raw_template()
    {
        var store = new MemoryStore(WritingStyleDocument.Default);
        var vm = new WritingStylesPageViewModel(store);
        await vm.LoadAsync();

        var coding = vm.Profiles.Single(p => p.Id == WritingStyleDocument.CodingProfileId);
        coding.AiAutoMatchEnabled = false;
        coding.MarkdownTemplate = "## Hello\n\n- item **one**\n\n{{content}}";
        vm.AiAutoMatch = true;
        vm.SelectedProfile = coding;
        await vm.SaveAsync();

        var reloaded = await store.LoadAsync(CancellationToken.None);
        var saved = reloaded.Profiles.Single(p => p.Id == WritingStyleDocument.CodingProfileId);
        Assert.False(saved.AiAutoMatchEnabled);
        Assert.True(reloaded.AiAutoMatch);

        Assert.DoesNotContain("**one**", coding.PreviewText);
        Assert.Contains("• item one", coding.PreviewText);
        Assert.DoesNotContain("{{content}}", coding.PreviewText);
    }

    [Fact]
    public async Task Custom_styles_can_be_added_and_deleted()
    {
        var store = new MemoryStore(WritingStyleDocument.Default);
        var vm = new WritingStylesPageViewModel(store);
        await vm.LoadAsync();

        vm.AddProfile("My style");
        Assert.Equal(8, vm.Profiles.Count);
        Assert.False(vm.SelectedProfile!.IsBuiltIn);
        Assert.True(vm.SelectedProfile.CanDelete);

        await vm.DeleteSelectedAsync();
        Assert.Equal(7, vm.Profiles.Count);
    }

    private sealed class MemoryStore(WritingStyleDocument document) : IWritingStyleStore
    {
        private WritingStyleDocument current = document;

        public ValueTask<WritingStyleDocument> LoadAsync(CancellationToken cancellationToken) =>
            ValueTask.FromResult(current);

        public ValueTask SaveAsync(WritingStyleDocument value, CancellationToken cancellationToken)
        {
            current = value.Normalize();
            return ValueTask.CompletedTask;
        }
    }
}
