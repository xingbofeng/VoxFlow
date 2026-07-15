using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.FileTranscription;

public interface IFileTranscriptionJobRepository
{
    void Create(FileTranscriptionJob job);

    FileTranscriptionJob? Get(string id);

    IReadOnlyList<FileTranscriptionJob> List();

    bool Update(FileTranscriptionJob job);

    bool Delete(string id);

    int MarkRunningAsInterrupted();
}

public interface IFileTranscriptionSegmentRepository
{
    void Upsert(FileTranscriptionSegment segment);

    IReadOnlyList<FileTranscriptionSegment> ListByJob(string jobId);

    int DeleteByJob(string jobId);

    int MarkRunningAsInterrupted();
}
