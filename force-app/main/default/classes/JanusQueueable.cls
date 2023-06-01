public with sharing class JanusQueueable implements Queueable {
    public List<Id> customerIds;
    public Janus.BatchConfig config;
    private Boolean skipDML = AssetManagementProcessTask.skipDML;
    public JanusQueueable(List<Id> customerIds) {
        this.customerIds = customerIds;
        this.config = Janus.config;
    }
    public void execute(QueueableContext ctx) {
        AssetManagementProcessTask.skipDML = this.skipDML;
        System.debug('JanusQueueable.execute - SETTING SKIP DML: ' + this.skipDML);
        Id customerId = this.customerIds.remove(0);
        Janus.config = this.config;
        Janus.runForCustomer(customerId, new JanusFinalizer(this.customerIds.clone(), ctx.getJobId()));
    }

    public class JanusFinalizer implements Serenity.SerenityFinalizer {
        private List<Id> remaining;
        public Janus.BatchConfig config;
        private Boolean skipDML = AssetManagementProcessTask.skipDML;
        public Id jobId;
        public JanusFinalizer (List<Id> remaining, Id jobId) {
            this.remaining = remaining;
            this.config = Janus.config;
            this.jobId = jobId;
        }
        public void execute() {
            this.execute(null);
        }
        public void execute(StagedDatabase.State dbState) {
            AssetManagementProcessTask.skipDML = this.skipDML;
            System.debug('JanusFinalizer.execute - SETTING SKIP DML: ' + this.skipDML);
            Janus.config = this.config;
            if(dbState != null) {
                try {
                    StagedDatabase.restore(dbState);
                    Janus.reflect();
                } catch (Exception e) {
                    AssetManagementLog.logError(e, null, 'Migration Data Update');
                }
            }
            if(remaining.size() > 0) {
                System.enqueueJob(new JanusQueueable(remaining));
            } else {
                // TODO: generate renewals.
                AssetManagementLog.logSuccess(jobId, 'Customer Asset Load Batch');
            }
        }
    }
}