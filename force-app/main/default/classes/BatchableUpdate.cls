/**
 * A dead-simple batchable implementation to support update of large volumes of records
 */
public with sharing class BatchableUpdate implements Database.Batchable<SObject> {
    List<SObject> records;
    public BatchableUpdate(List<SObject> records) {
        this.records = records;
    }
    public Iterable<SObject> start (Database.BatchableContext bc) {
        return this.records;
    }
    public void execute (Database.BatchableContext bc, List<SObject> records) {
        Integer typeCount = 0;
        String typePrefix = null;
        List<SObject> updateBatch = new List<SObject>();
        for (SObject record : records) {
            String recTypePrefix = String.valueOf(record.Id).substring(0,3);
            if(recTypePrefix != typePrefix){
                typePrefix = recTypePrefix;
                typeCount++;
            }
            if(typeCount >= 10) {
                update updateBatch;
                updateBatch = new List<SObject>();
                typeCount = 0;
                typePrefix = null;
            }
            updateBatch.add(record);
        }
        update updateBatch;
    }
    public void finish (Database.BatchableContext bc) {

    }
}