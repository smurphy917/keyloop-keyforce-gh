public with sharing class JanusBatchable implements Database.Batchable<Janus.DataBlock>, Database.AllowsCallouts, Database.Stateful {
    private Janus.BatchConfig config;
    private StagedDatabase.State dbState;
    private List<Janus.DataBlock> blocks;
    private Serenity.SerenityFinalizer finalizer;
    private Boolean skipDML = AssetManagementProcessTask.skipDML;
    public JanusBatchable(){}
    public JanusBatchable(List<Janus.DataBlock> blocks, Serenity.SerenityFinalizer finalizer) {
        this.blocks = blocks;
        this.finalizer = finalizer;
        this.config = Janus.config;
    }
    public List<Janus.DataBlock> start(Database.BatchableContext bc) {
        this.dbState = StagedDatabase.getState();
        if(this.blocks != null) {
            
            return this.blocks;
        }
        return Janus.getBlocks();
    }
    public void execute(Database.BatchableContext bc, List<Janus.DataBlock> blocks) {
        try {
            StagedDatabase.restore(this.dbState);
            for (Janus.DataBlock block : blocks) {
                Janus.buildForBlock(block);
            }
            this.dbState = StagedDatabase.getState();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, e.getMessage() + '\n' + e.getStackTraceString());
            System.abortJob(bc.getJobId());
        }
    }
    public void finish(Database.BatchableContext bc){
        StagedDatabase.restore(this.dbState);
        AssetManagementProcessTask.skipDML = this.skipDML;
        System.debug('JanusBatchable - SETTING SKIP DML: ' + this.skipDML);
        Serenity.config = this.config.assetConfig;
        if(this.finalizer != null) {
            Serenity.process(finalizer);
        } else {
            Serenity.process();
        }
    }
}