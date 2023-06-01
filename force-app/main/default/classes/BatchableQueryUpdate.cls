public with sharing class BatchableQueryUpdate implements Database.Batchable<SObject> {

    public String query;
    public BatchQuery batchQuery;
    public BatchUpdate batchUpdate;

    public BatchableQueryUpdate(String query, BatchQuery batchQuery, BatchUpdate batchUpdate) {
        this.query = query;
        this.batchQuery = batchQuery;
        this.batchUpdate = batchUpdate;
    }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator(this.query);
    }

    public void execute(Database.BatchableContext ctx, List<SObject> objs) {
        Map<Id,SObject> sourceMap = this.batchQuery.execute(objs);
        this.batchUpdate.execute(objs, sourceMap);
        update objs;
    }
    
    public void finish(Database.BatchableContext ctx) {}

    public interface BatchQuery {
        Map<Id,SObject> execute(List<SObject> batchRecords);
    }
    public interface BatchUpdate {
        void execute(List<SObject> batchRecords, Map<Id,SObject> sourceRecords);
    }
}