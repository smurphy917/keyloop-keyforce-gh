public with sharing class ActionBatchUpdate {
    public class InvocableParameter {
        @InvocableVariable(label='Records' required=true)
        public List<SObject> records;
        @InvocableVariable(label='Batch Size' required=true)
        public Integer batchSize;
    }
    public class InvocableResult {
        @InvocableVariable(label='Job Id')
        public Id jobId;
    }
    @InvocableMethod(label='Batch Update' description='Update records via apex batch')
    public static List<InvocableResult> InvocableBatchUpdate(List<InvocableParameter> params) {
        List<InvocableResult> results = new List<InvocableResult>();
        for (InvocableParameter p : params) {
            InvocableResult result = new InvocableResult();
            result.jobId = Database.executeBatch(new BatchableUpdate(p.records), p.batchSize);
            results.add(result);
        }
        return results;
    }
}