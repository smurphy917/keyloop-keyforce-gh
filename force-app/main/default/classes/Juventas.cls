public with sharing class Juventas {

    public static BatchConfig config;
    
    /*
    public static void immortalise(BatchConfig inputConfig){
        config = inputConfig;

        List<Asset> assets = [
            SELECT 
                Id,
                LifecycleEndDate,
                Aggregate_Asset__r.RootAssetId,
                Aggregate_Asset__r.RootAsset.LifecycleEndDate
            FROM Asset
            WHERE 
                Status = 'Installed' AND
                Aggregate_Asset__c != null AND
                ParentId != null AND
                Co_Terminus__c = false AND 
                Id NOT IN (
                    SELECT Asset__c 
                    FROM SBQQ__QuoteLine__c 
                    WHERE SBQQ__Renewal__c = true
                )
            ORDER BY
                Aggregate_Asset__r.RootAssetId,
                LifecycleEndDate
        ];
        String blockKey;
        String key;
        List<Id> renewalAssetIds = new List<Id>();
        List<DataBlock> blocks = new List<DataBlock>();
        Asset lastAsset;
        for (Asset a : assets) {
            key = a.Aggregate_Asset__r.RootAssetId + '|' + a.LifecycleEndDate;
            if(key!= blockKey) {
                blocks.add(new DataBlock(
                    a.Aggregate_Asset__r.RootAssetId,
                    Datetime.newInstanceGmt(a.LifecycleEndDate.dateGmt(), Time.newInstance(0,0,0,0)),
                    a.LifecycleEndDate.dateGmt().addDays(1),
                    a.Aggregate_Asset__r.LifecycleEndDate.dateGmt()
                ));
                renewalAssetIds = new List<Id>();
                blockKey = key;
            }
            renewalAssetIds.add(a.Id);
            lastAsset = a;
        }
        blocks.add(new DataBlock(
            lastAsset.Aggregate_Asset__r.RootAssetId,
            renewalAssetIds,
            Datetime.newInstanceGmt(lastAsset.LifecycleEndDate.dateGmt(), Time.newInstance(0,0,0,0)),
            lastAsset.LifecycleEndDate.dateGmt().addDays(1),
            lastAsset.Aggregate_Asset__r.LifecycleEndDate.dateGmt()
        ));
        Database.executeBatch(new JuventasBatch(blocks), config.blockBatchSize);
    }
    */
    public static Date getRenewalEndDate (Date startDate, Date targetCoTermDate, Decimal renewalTerm) {
        if(renewalTerm == null) {
            renewalTerm = 12;
        }
        Decimal monthsDiff = startDate.monthsBetween(targetCoTermDate);
        if(monthsDiff <= renewalTerm) {
            return targetCoTermDate;
        }
        Integer wholeTermsDiff = Integer.valueOf(monthsDiff / renewalTerm);
        return targetCoTermDate.addMonths(Integer.valueOf(-1 * wholeTermsDiff * renewalTerm));
    }

    public static void immortaliseBlock(DataBlock block) {
        // public static Id GenerateAndSave(Id assetId, Map<Id,Juventas.IncrementalRenewal> assetQuantityMap, Datetime asOf, Date startDate, Date endDate, TransactionType type, List<Id> accountIds, Id oppOrQuoteId, String oppSubType) {
        Thrill.GenerateAndSave(
            block.rootAssetId, //root asset id
            block.assets, // asset quantity map
            Datetime.newInstanceGmt(block.startDate.addDays(-1), Time.newInstance(23,59,59,0)), // as-of datetime
            block.startDate, // start date override
            block.endDate, // end date override
            Thrill.TransactionType.Renewal, // type
            null, // account ids
            null, // opp or quote id
            'Renewal' // opp sub type
        );
    }

    public class DataBlock implements Comparable {
        public Id customerId;
        public Id rootAssetId;
        public Map<Id, IncrementalRenewal> assets;
        public Date startDate;
        public Date endDate;
        public DataBlock (Id customerId, Id rootAssetId, Date startDate, Date enddate) {
            this.customerId = customerId;
            this.rootAssetId = rootAssetId;
            this.assets = new Map<Id, IncrementalRenewal>();
            this.startDate = startDate;
            this.endDate = endDate;
        }
        public Integer compareTo(Object comp) {
            return String.valueOf(this.customerId).compareTo(String.valueOf(((DataBlock) comp).customerId));
        }
    }

    public class IncrementalRenewal {
        public Id assetId;
        public Decimal deltaQuantity;
        public Decimal targetQuantity;
        public Decimal unitMrr;
        public Decimal priorQuantity {
            get {
                if(this.targetQuantity != null) {
                    return targetQuantity - deltaQuantity;
                } else {
                    return 0;
                }
            }
        }
        public IncrementalRenewal(Id assetId, Decimal deltaQuantity, Decimal targetQuantity) {
            this.assetId = assetId;
            this.deltaQuantity = deltaQuantity;
            this.targetQuantity = targetQuantity;
        }
        public IncrementalRenewal(Id assetId, Decimal deltaQuantity, Decimal targetQuantity, Decimal unitMrr) {
            this.assetId = assetId;
            this.deltaQuantity = deltaQuantity;
            this.targetQuantity = targetQuantity;
            this.unitMrr = unitMrr;
        }
    }

    public class BatchConfig {
        public Integer blockBatchSize = 1;
        public Integer concurrentBatches = 5;
        public Integer recordLimit;
        public String queryStr;

        public BatchConfig(Integer recordLimit, String queryStr) {
            this.recordLimit = recordLimit;
            this.queryStr = queryStr;
        }
    }

}