public with sharing class ReignBatchable implements Database.Batchable<Integer>, Database.Stateful {
    Janus.BatchConfig config;
    List<Id> finalIds = new List<Id>();
    List<List<Id>> queueableBatches;
    Id breakPoint;
    String baseWhere = 'Product__r.ParentProduct__c != null AND Product__r.AssetConversion__c != null AND Asset__c = null';
    public ReignBatchable(Janus.BatchConfig config) {
        this.config = config;
    }
    public List<Integer> start(Database.BatchableContext ctx) {
        Integer rowCount = (Integer) [SELECT COUNT(Id) rowCount FROM Asset_Migration_Record__c WHERE Product__r.ParentProduct__c != null AND Product__r.AssetConversion__c != null AND Asset__c = null][0].get('rowCount');
        List<Integer> idxs = new List<Integer>();
        Integer count = 0;
        for (Integer bogus : new Integer[(rowCount / 50000.0).round(System.RoundingMode.UP).intValue()]) {
            idxs.add(count);
            count++;
        }
        for (Integer jdx = 0; jdx < this.config.concurrentBatches; jdx++) {
            idxs.add(100 + jdx);
        }
        System.debug(idxs);
        // System.assert(false);
        return idxs;
    }
    public void execute(Database.BatchableContext ctx, List<Integer> idxs) {
        for (Integer idx : idxs) {
            if(idx >= 100) {
                // this is a signal that the finalIds has been populated.
                if(this.queueableBatches == null) {
                    this.queueableBatches = Janus.reign(this.config, this.finalIds, false);
                }
                Integer batchIdx = idx - 100;
                List<Id> batchIds;
                if(this.queueableBatches.size() > batchIdx) {
                    batchIds = this.queueableBatches[batchIdx];
                } else {
                    System.debug('NO IDs FOR BATCH IDX: ' + batchIdx);
                    return;
                }
                System.debug('BATCH IDS: ' + batchIds);
                Janus.config = this.config;
                System.enqueueJob(new JanusQueueable(batchIds));
                continue;
            }
            String whereClause = baseWhere;
            if(breakPoint != null) {
                whereClause += ' AND Customer__c > \'' + this.breakPoint + '\'';
            }
            List<Asset_Migration_Record__c> rows = (List<Asset_Migration_Record__c>) Database.query('SELECT Customer__c FROM Asset_Migration_Record__c WHERE ' + whereClause + ' ORDER BY Customer__c ASC LIMIT 50000');
            // System.debug('BATCH ROWS:' + rows.size());
            Id working;
            for (Asset_Migration_Record__c row : rows) {
                if(row.Customer__c != working){
                    this.finalIds.add(row.Customer__c);
                    working = row.Customer__c;
                }
            }
            this.breakPoint = working;
        }
    }
    public void finish(Database.BatchableContext ctx) {
        // Janus.reign(this.config, this.finalIds);

    }
}