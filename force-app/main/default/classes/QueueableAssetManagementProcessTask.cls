public with sharing class QueueableAssetManagementProcessTask implements Queueable {
    AssetManagementProcessTask task;
    public QueueableAssetManagementProcessTask(AssetManagementProcessTask task) {
        this.task = task;
    }
    public void execute(QueueableContext ctx) {
        this.task.process();
    }
}