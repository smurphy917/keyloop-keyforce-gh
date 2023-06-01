public without sharing class BatchableProcessAssetManagementTasks implements Database.Batchable<AssetTaskBlock>, Database.AllowsCallouts, Database.Stateful {
    List<AssetManagementProcessTask> tasks = new List<AssetManagementProcessTask>();
    // List<AssetTaskBlock> blocks;
    String sourceId;
    StagedDatabase.State dbState;
    private Exception[] errors;
    private Integer successCount;
    private String sourceAction;
    private Serenity.BatchConfig config;
    private Serenity.SerenityFinalizer finalizer;


    public BatchableProcessAssetManagementTasks(){}
    
    public BatchableProcessAssetManagementTasks(List<AssetManagementProcessTask> tasks, StagedDatabase.State state, String sourceId, String sourceAction, Serenity.SerenityFinalizer finalizer) {
        this.tasks = tasks;
        this.dbState = state;
        this.sourceId = sourceId;
        this.sourceAction = sourceAction;
        this.successCount = 0;
        this.errors = new Exception[]{};
        this.config = Serenity.config;
        this.finalizer = finalizer;
    }
    
    public Iterable<AssetTaskBlock> start (Database.BatchableContext bc) {
        Serenity.config = this.config;
        return Serenity.buildBlocks(this.tasks);
    }
    public void execute (Database.BatchableContext bc, List<AssetTaskBlock> blocks) {
        StagedDatabase.restore(dbState); // Restore for each transaction
        String dbJson = StagedDatabase.toJSON();
        System.debug('*** INITIAL STATE ***\n' + dbJson);
        for (AssetTaskBlock block : blocks) {
            try {
                this.successCount += block.process();
            } catch (Exception e) {
                this.errors.add(e);
                if(e.getTypeName() == 'AssetManagementProcessTask.TaskException') {
                    this.successCount += ((AssetManagementProcessTask.TaskException) e).successCount;
                } else {
                    System.debug('EXCEPTION TYPE: ' + e.getTypeName());
                }
            }
        }
        this.dbState = StagedDatabase.getState();
        dbJson = StagedDatabase.toJSON();
        System.debug('*** FINAL STATE ***\n' + dbJson);
    }
    public void finish (Database.BatchableContext bc) {
        Map<String,Object> flowInputs = new Map<String,Object>();
        flowInputs.put('OrderId', this.sourceId);
        Flow.Interview.createInterview('Asset_Processing_Complete', flowInputs).start();
        // EventBus.publish(new AssetProcessingComplete__e(
        //    OrderId__c = this.sourceId
        //));
        AssetManagementLog.logBatch(this.sourceId, this.sourceAction, this.successCount, this.errors);
        if(this.finalizer != null) {
            this.finalizer.execute(this.dbState);
        }
    }
}