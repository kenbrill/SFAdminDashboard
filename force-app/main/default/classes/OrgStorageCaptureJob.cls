public class OrgStorageCaptureJob implements Queueable, Database.AllowsCallouts {
    public void execute(QueueableContext ctx) {
        OrgStorageService.captureSnapshot();
    }
}
