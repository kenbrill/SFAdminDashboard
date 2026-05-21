public class OrgStorageScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        System.enqueueJob(new OrgStorageCaptureJob());
    }
}
