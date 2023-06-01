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
    private Boolean skipDML = AssetManagementProcessTask.skipDML;
    private String namedCredential;

    private Serenity.AsyncAction action;
    private Date inputDate;

    public BatchableProcessAssetManagementTasks(){}

    public BatchableProcessAssetManagementTasks(Serenity.AsyncAction action, Id sourceId, Date inputDate) {
        this.tasks = null;
        this.dbState = StagedDatabase.getState();
        this.sourceId = sourceId;
        this.sourceAction = action.name();
        this.action = action;
        this.errors = new Exception[]{};
        this.config = Serenity.config;
        this.successCount = 0;
        this.inputDate = inputDate;
        if(this.config.namedCredentials != null) {
            this.namedCredential = this.config.namedCredentials[0];
        }
    }
    
    public BatchableProcessAssetManagementTasks(List<AssetManagementProcessTask> tasks, StagedDatabase.State state, String sourceId, String sourceAction, Serenity.SerenityFinalizer finalizer) {
        this.tasks = tasks;
        this.dbState = state;
        this.sourceId = sourceId;
        this.sourceAction = sourceAction;
        this.successCount = 0;
        this.errors = new Exception[]{};
        this.config = Serenity.config;
        this.finalizer = finalizer;
        if(this.config.namedCredentials != null) {
            this.namedCredential = this.config.namedCredentials[0];
        }
    }
    
    public Iterable<AssetTaskBlock> start (Database.BatchableContext bc) {
        Serenity.config = this.config;
        if(this.tasks != null) {
            return Serenity.buildBlocks(this.tasks);
        } else if (this.action != null) {
            StagedDatabase.restore(this.dbState);
            Serenity.runAsync = true;
            switch on this.action {
                when Order {
                    Serenity.Order(this.sourceId);
                }
                when OrderUpdate {
                    Serenity.OrderUpdate(this.sourceId);
                }
                when CancelAll {
                    Serenity.CancelAll(this.sourceId);
                }
                when CancelOne {
                    Serenity.CancelOne(this.sourceId);
                }
                when CancelTree {
                    Serenity.CancelTree(this.sourceId);
                }
                when EndDate {
                    Serenity.EndDate(this.sourceId, this.inputDate);
                    Serenity.process();
                }
            }
            // this.sourceAction = Serenity.sourceAction;
            this.dbState = StagedDatabase.getState();
            List<AssetTaskBlock> blocks = Serenity.buildBlocks(Serenity.queue);
            // System.debug('ALL BLOCKS:' + JSON.serialize(blocks));
            return blocks;
        }
        return null;
    }
    public void execute (Database.BatchableContext bc, List<AssetTaskBlock> blocks) {
        StagedDatabase.restore(dbState); // Restore for each transaction
        AssetManagementProcessTask.skipDML = this.skipDML;
        // System.debug('BatchableProcessAssetManagementTask.execute - SETTING SKIP DML: ' + this.skipDML);
        // String dbJson = StagedDatabase.toJSON();
        // System.debug('*** INITIAL STATE ***\n' + dbJson);
        Integer idx = 0;
        Integer retryCount = 0;
        while (idx < blocks.size() && retryCount < 5) {
        // for (AssetTaskBlock block : blocks) {
            AssetTaskBlock block = blocks[idx];
            try {
                this.successCount += block.process(this.namedCredential);
                idx++;
                retryCount = 0;
            } catch (Exception e) {
                if(e.getTypeName() == 'AssetManagementProcessTask.RequestLimitExceededException') {
                    if(this.config.namedCredentials != null) {
                        Integer credIdx = this.config.namedCredentials.indexOf(this.namedCredential);
                        this.namedCredential = this.config.namedCredentials[Math.mod(credIdx + 1,this.config.namedCredentials.size())];
                    }
                    retryCount++;
                    continue;
                }
                this.errors.add(e);
                idx++;
                if(e.getTypeName() == 'AssetManagementProcessTask.TaskException') {
                    this.successCount += ((AssetManagementProcessTask.TaskException) e).successCount;
                } else {
                    System.debug('EXCEPTION TYPE: ' + e.getTypeName());
                    System.debug(LoggingLevel.ERROR,e.getStackTraceString());
                }
            }
        }
        this.dbState = StagedDatabase.getState();
        // dbJson = StagedDatabase.toJSON();
        // System.debug('*** FINAL STATE ***\n' + dbJson);
    }
    public void finish (Database.BatchableContext bc) {
        if(this.sourceId != null) {
            if(Id.valueOf(this.sourceId).getSObjectType().getDescribe().getName() == 'Order') {
                Map<String,Object> flowInputs = new Map<String,Object>();
                flowInputs.put('OrderId', this.sourceId);
                Flow.Interview.createInterview('Asset_Processing_Complete', flowInputs).start();
            }
        }
        AssetManagementLog.logBatch(this.sourceId, this.sourceAction, this.successCount, this.errors);
        if(this.finalizer != null) {
            AssetManagementProcessTask.skipDML = this.skipDML;
            // System.debug('BatchangeProcessAssetManagementTask.finish - SETTING SKIP DML: ' + this.skipDML);
            this.finalizer.execute(this.dbState);
        }
        /*
        if(this.errors.size() > 0) {
            throw new BatchException('Completed with ' + this.errors.size() + ' errors.');
        }
        */
    }
    
    public class BatchException extends Exception {

    }
}