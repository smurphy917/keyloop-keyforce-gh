/**
* @author Pierce Washington Ltd.
* @date 2022-11-28
*
* @group Asset Management
* @group-content ../../ApexDocContent/Janus.md
*
* @description Manage data migration by loading from staged records (Asset_Migration_Record__c) to
* lifecycle-managed assets. Utilises some elements of Serenity.cls for common functionality.
*/
public class Janus {

    public static BatchConfig config = new BatchConfig();

    private static Datetime currentTime = Datetime.now();

    public Janus() {
    }

    public class DataRow {
        public Account Account;
        public Account Site;
        public String ProductCode;
    }

    public static List<List<Id>> reign(BatchConfig inputConfig){
        return reign(inputConfig, null);
    }
    public static List<List<Id>> reign(BatchConfig inputConfig, List<Id> rawCustomerIds){
        return reign(inputConfig, rawCustomerIds, true);
    }
    /**
    * @description Primary entry method. Generates and executes a batch (JanusBatchable) of independent customers.
    */
    public static List<List<Id>> reign(BatchConfig inputConfig, List<Id> rawCustomerIds, Boolean queueJobs){
        // List<DataRow> rows = 
        //     (List<DataRow>) DataWeave.Script.createScript('csvToDataRow')
        //     .execute(new Map<String,Object>{
        //         'records' => [
        //             SELECT Body
        //             FROM StaticResource
        //             WHERE Name = 'testAssetMigrationData'
        //             LIMIT 1
        //         ].Body.toString()
        //     })
        //     .getValue();
        // Database.QueryLocator loc = Database.getQueryLocator([
        //     SELECT Customer__c, Site__c
        //     FROM Asset_Migration_Record__c
        //     GROUP BY Customer__c, Site__c
        // ]);
        // Database.executeBatch(new JanusBatchable(), 1);
        config = inputConfig;
        if(rawCustomerIds == null) {
            List<AggregateResult> rows = [
                SELECT Customer__c 
                FROM Asset_Migration_Record__c 
                WHERE Product__r.ParentProduct__c != null AND Product__r.AssetConversion__c != null AND Asset__c = null AND Customer__c != null AND Site__c != null
                GROUP BY Customer__c
            ];
            rawCustomerIds = new List<Id>();
            for (AggregateResult row : rows) {
                rawCustomerIds.add((Id) row.get('Customer__c'));
            }
        }
        List<List<Id>> customerIds = new List<List<Id>>();
        Integer concurrentBatches = config.concurrentBatches;
        if(concurrentBatches == null) {
            concurrentBatches = 1;
        }
        for (Integer j = 0; j < concurrentBatches; j++) {
            customerIds.add(new List<Id>());
        }
        for (Integer i = 0; (i * concurrentBatches) < rawCustomerIds.size(); i++) {
            for (Integer j = 0; j < concurrentBatches; j ++) {
                if(j >= customerIds.size()) {
                    break;
                }
                List<Id> batchIds = customerIds.get(j);
                Integer idx = (i * concurrentBatches) + j;
                if(idx < rawCustomerIds.size()) {
                    batchIds.add(rawCustomerIds[idx]);
                }
            }
            
            if(config.customerLimit != null && customerIds.get(0).size() >= config.customerLimit) {
                break;
            }
        }

        if(config.assetConfig.namedCredentials == null || config.assetConfig.namedCredentials.size() == 0) {
            List<NamedCredential> creds = [SELECT DeveloperName FROM NamedCredential WHERE DeveloperName LIKE 'Salesforce_Internal_%'];
            List<String> namedCredentials;
            if(creds.size() > 0) {
                namedCredentials = new List<String>();
                for (NamedCredential cred : creds) {
                    namedCredentials.add(cred.DeveloperName);
                }
                config.assetConfig.namedCredentials = namedCredentials;
            }
        }
        for (Integer idx = customerIds.size() - 1; idx >= 0; idx--){
            if(customerIds[idx].size() == 0) {
                customerIds.remove(idx);
            }
        }
        if(queueJobs) {
            for (List<Id> batchList : customerIds) {
                System.debug('Running for ' + batchList.size() + ' customers...');
                System.debug(JSON.serialize(batchList));
                System.enqueueJob(new JanusQueueable(batchList));
            }
        }
        return customerIds;
    }

    static List<String> extendedRowFields {
        get {
            return new String[]{
                'Product__r.ParentProduct__c',
                'Product__r.SBQQ__ChargeType__c',
                'Product__r.MandatoryFor__c',
                'Product__r.Name',
                'Product__r.ParentProduct__r.ParentProduct__c',
                'Product__r.ParentProduct__r.SBQQ__ChargeType__c',
                'Product__r.ParentProduct__r.MandatoryFor__c',
                'Product__r.ParentProduct__r.Name'
            };
        }
    }
    public static List<DataBlock> getBlocks() {
        return getBlocks(null);
    }
    public static List<DataBlock> getBlocks(Id customerId) {
        String whereClause = 'Customer__c != null AND Product__r.ParentProduct__c != null AND Product__r.AssetConversion__c != null AND Asset__c = null ORDER BY Customer__c, Site__c, Product__r.ParentProduct__c';
        if(customerId != null) {
            whereClause = 'Customer__c = \'' + customerId + '\' AND Product__r.ParentProduct__c != null AND Product__r.AssetConversion__c != null AND Asset__c = null ORDER BY Customer__c, Site__c, Product__r.ParentProduct__c, Start_Date__c';
        }
        List<Asset_Migration_Record__c> rows = (List<Asset_Migration_Record__c>) PWUtils.selectStar(
            'Asset_Migration_Record__c',
            whereClause,
            extendedRowFields
        );
        String rowKey;
        String blockKey;
        List<DataBlock> blocks = new List<DataBlock>();
        DataBlock block;
        for (Asset_Migration_Record__c row : rows) {
            rowKey = row.Customer__c + '|' + row.Site__c + '|' + row.Product__r.ParentProduct__c;
            if(rowKey != blockKey) {
                block = new DataBlock(row.Customer__c, row.Product__r.ParentProduct__r);
                blocks.add(block);
                blockKey = rowKey;
            }
            block.add(row);
        }
        return blocks;
    }

    public static void runForCustomer (Id customerId, Serenity.SerenityFinalizer finalizer) {
        List<DataBlock> blocks = getBlocks(customerId);
        if(config.blockLimitPerCustomer != null) {
            blocks = (List<DataBlock>) PWUtils.slice(blocks,0,config.blockLimitPerCustomer);
        }
        System.debug('Starting batch run of ' + blocks.size() + ' blocks...');
        Database.executeBatch(new JanusBatchable(blocks, finalizer), config.blockBatchSize);
    }

    /**
    * @description Generate records for a single customer (bill-to)
    * @param accountId Id of the account to generate records for
    */
    /*
    public static void buildForCustomer (Id accountId) {
        List<Asset_Migration_Record__c> rows = (List<Asset_Migration_Record__c>) PWUtils.selectStar(
            'Asset_Migration_Record__c',
            'Customer__c = \'' + accountId + '\' AND Product__r.ParentProduct__c != null ORDER BY Site__c, Product__r.ParentProduct__c',
            extendedRowFields
        );
        String blockKey = String.join(
            new String[]{rows[0].Site__c, rows[0].Product__r.ParentProduct__c},
            '|'
        );
        List<Asset_Migration_Record__c> blockRows = new List<Asset_Migration_Record__c>();
        for (Asset_Migration_Record__c row : rows) {
            String rowKey = row.Site__c + '|' + row.Product__r.ParentProduct__c;
            if(rowKey != blockKey) {
                DataBlock block = new DataBlock(accountId, blockRows[0].Product__r.ParentProduct__r);
                block.rows.addAll(blockRows);
                buildForBlock(block);
                blockRows = new List<Asset_Migration_Record__c>();
                blockKey = rowKey;
            }
            blockRows.add(row);
        }
    }
    */

    /**
    * @description Generate records for a block--a unique combination of site and proposition (within a customer)
    * @param rows Migration rows (Asset_Migration_Record__c) to buld from
    * @param customerId customer (bill-to) Id to aggregate to
    */
    public static void buildForBlock(DataBlock block) {
        System.debug(LoggingLevel.INFO,'Starting block of ' + block.rows.size() + ' records...');
        System.debug(JSON.serialize(block));
        Asset_Migration_Record__c root = block.rows[0].clone(
            false, // clear Id
            true // deep clone
        );
        root.Source_Reference__c = 'Added during data transformation';
        root.Product__c = block.rootProduct.Id;
        root.Product__r = block.rootProduct;
        root.Quantity__c = 1;
        for (Asset_Migration_Record__c row : block.rows) {
            if(row.Original_Start_Date__c < root.Original_Start_Date__c) {
                root.Original_Start_Date__c = row.Original_Start_Date__c;
            }
            if(row.Start_Date__c < root.Start_Date__c) {
                root.Start_Date__c = row.Start_Date__c;
            }
            if(row.End_Date__c > root.End_Date__c) {
                root.End_Date__c = row.End_Date__c;
            }
        }
        root.Start_Date__c = root.Original_Start_Date__c;
        List<Asset_Migration_Record__c> allRows = new List<Asset_Migration_Record__c>();
        allRows.add(root);
        allRows.addAll(block.rows);
        System.debug(JSON.serialize(allRows));
        NestedObject blockTree = new NestedObject(
            allRows,
            'Product__c',
            'Product__r.ParentProduct__c'
        );
        // Re-parent any items with a 'mandatory-for' relationship
        for (NestedObject node : blockTree.all()) {
            Integer[] removeIdxs = new Integer[]{};
            if(node.children != null) {
                for (Integer i = 0; i < node.children.size(); i++) {
                    NestedObject child = node.children[i];
                    Id mandatoryFor = (Id) node.obj.get('Product__r.MandatoryFor__c');
                    if(mandatoryFor != null) {
                        System.debug('Re-parenting...');
                        removeIdxs.add(i);
                        NestedObject newParent = blockTree.findByKey('Product__c', mandatoryFor);
                        newParent.addChild(child);
                    }
                }
            }
            // System.debug('removeIdxs: ' + removeIdxs);
            // System.debug('node.children: ' + JSON.serialize(node.children));
            for (Integer j = removeIdxs.size() - 1; j >= 0; j--) {
                Integer idx = removeIdxs[j];
                node.children.remove(idx);
            }
        }
        // Consolidate tree by product
        for (NestedObject node : blockTree.all()) {
            NestedObject match = blockTree.findByKey('Product2Id', (String) node.obj.get('Product__c'));
            if(match != null) {
                addPeriod((StagedAsset) match.obj, node.obj);
                addSource((StagedAsset) match.obj, node.obj);
                updateGoLiveDate((StagedAsset) match.obj, node.obj);
                setStatus((StagedAsset) match.obj);
                addSerialNumber(((StagedAsset) match.obj), node.obj);
                blockTree.remove(node.obj.Id);
            } else {
                StagedAsset a = createAsset(node.obj);
                node.replaceObject(a);
                // a.ParentId = node.parentId;
                // node.setData(Serenity.DataKeys.IS_NEW.name(), true);
                if(node.parentId != null) {
                    a.setLookup('Parent', (StagedAsset) blockTree.findById(node.parentId).obj);
                }
            }
        }
        Serenity_v1.rollUpValues(blockTree);
        Serenity_v1.aggregate(blockTree, block.accountId);
    }

    public static Double getMrr(NestedObject.Nestable record) {
        if((String) record.get('Product__r.SBQQ__ChargeType__c') == 'Recurring') {
            return ((Double) record.get('Price__c')) * ((Double) record.get('Quantity__c'));
        } else {
            return 0.0;
        }
    }
    public static Double monthsBetween(Date a, Date b) {
        return a.daysBetween(b) * 12 / 365;
    }

    public static StagedAsset createAsset(NestedObject.Nestable record) {
        System.debug('CREATING ASSET: ' + JSON.serialize(record));
        StagedAsset a = new StagedAsset();
        if(record.Id != null) {
            a.sourceIds.add(record.Id);
        }
        a.set('Revision__c', 1);
        a.Name = (String) record.get('Product__r.Name');
        String currencyCode = (String) record.get('CurrencyIsoCode');
        if(currencyCode == null) {
            currencyCode = 'GBP';
        }
        a.CurrencyIsoCode = currencyCode;
        a.AccountId = (Id) record.get('Site__c');
        a.Product2Id = (Id) record.get('Product__c');
        a.set('Go_Live_Date__c', record.get('Original_Start_Date__c'));

        Double mrr = getMrr(record); 

        a.AssetStatePeriods.addAll(createPeriods(record));
        setStatus(a);
        StagedAssetAction aa = new StagedAssetAction();
        aa.CategoryEnum = StagedAssetAction.Category.Other;
        aa.ActionDate = Datetime.now();
        if(record.get('Product__r.SBQQ__ChargeType__c') == 'One-Time') {
            aa.Amount = ((Double) record.get('Price__c')) * ((Double) record.get('Quantity__c'));
        } else if (a.AssetStatePeriods.size() > 1) {
            try {
                aa.Amount = mrr * monthsBetween(a.AssetStatePeriods[0].StartDate.dateGmt(), a.AssetStatePeriods[1].EndDate.dateGmt());
            } catch (Exception e) {
                System.debug(a.AssetStatePeriods);
                throw e;
            }
        } else {
            aa.Amount = a.AssetStatePeriods[0].Amount;
        }
        aa.MrrChange = mrr;
        aa.QuantityChange = (Double) record.get('Quantity__c');
        String aasRef = (String) record.get('Source_Reference__c');
        if(aasRef == null) {
            aasRef = record.Id;
        }
        aa.AssetActionSources.add(
            new AssetActionSource(
                // ExternalReference = record.get('Sales_Order_Number__c'),
                // ExternalReferenceDataSource = 'Legacy System - Business Central'
                ExternalReference = aasRef,
                ExternalReferenceDataSource = 'Legacy Systems - Business Central'
            )
        );
        a.AssetActions.add(aa);
        a.initiate();
        StagedDatabase.put(a);

        if(a.AssetActions.size() > 1){
            System.debug(JSON.serialize(a));
            System.assert(false);
        }

        addSerialNumber(a, record);

        return a;
    }

    public static void setStatus(StagedAsset a) {
        String status = '';
        for (StagedAssetStatePeriod asp : a.AssetStatePeriods) {
            if(asp.StartDate <= currentTime && asp.EndDate >= currentTime) {
                status = 'Installed';
            } else if (asp.EndDate < currentTime && status != 'Installed' && status != 'Purchased') {
                status = 'Obsolete';
            } else if (asp.StartDate > currentTime && status != 'Installed') {
                status = 'Purchased';
            }
        }
        a.Status = status;
    }

    public static List<StagedAssetStatePeriod> createPeriods (NestedObject.Nestable record) {
        Double mrr = getMrr(record); 
        List<StagedAssetStatePeriod> periods = new List<StagedAssetStatePeriod>();
        Boolean hasOriginalPeriod = false;
        if(((Date) record.get('Original_Start_Date__c')) != ((Date) record.get('Start_Date__c'))) {
            hasOriginalPeriod = true;
            StagedAssetStatePeriod p1 = new StagedAssetStatePeriod();
            p1.StartDate = Datetime.newInstanceGmt((Date) record.get('Original_Start_Date__c'), Time.newInstance(0, 0, 0, 0));
            p1.EndDate = Datetime.newInstanceGmt((Date) record.get('Start_Date__c'), Time.newInstance(0, 0, 0, 0)).addSeconds(-1);
            p1.Quantity = (Double) record.get('Quantity__c');
            p1.Mrr = mrr;
            if(record.get('Product__r.SBQQ__ChargeType__c') == 'One-Time') {
                p1.oneTimeAmount = ((Double) record.get('Price__c')) * ((Double) record.get('Quantity__c'));
            }
            periods.add(p1);
        }
        // p1.Amount = mrr * monthsBetween(p1.StartDate.date(), p1.EndDate.date());

        StagedAssetStatePeriod p2 = new StagedAssetStatePeriod();
        p2.StartDate = Datetime.newInstanceGmt((Date) record.get('Start_Date__c'), Time.newInstance(0, 0, 0, 0));
        p2.EndDate = Datetime.newInstanceGmt((Date) record.get('End_Date__c'), Time.newInstance(23, 59, 59, 0));
        p2.Quantity = (Double) record.get('Quantity__c');
        p2.Mrr = mrr;
        if(!hasOriginalPeriod && record.get('Product__r.SBQQ__ChargeType__c') == 'One-Time') {
            p2.oneTimeAmount = ((Double) record.get('Price__c')) * ((Double) record.get('Quantity__c'));
        }
        periods.add(p2);
        // p2.Amount = mrr * monthsBetween(p2.StartDate.date(), p2.EndDate.date());     
        return periods;
    }

    public static void addPeriod(StagedAsset a, NestedObject.Nestable record) {
        List<StagedAssetStatePeriod> abnormalPeriods = new List<StagedAssetStatePeriod>();
        abnormalPeriods.addAll(a.AssetStatePeriods);
        abnormalPeriods.addAll(createPeriods(record));
        a.AssetStatePeriods = StagedAssetStatePeriod.fromList(TimePeriod.normalize(abnormalPeriods, new String[]{}, StagedAssetStatePeriod.class));
        // record.Id = a.Id;
    }

    public static void addSource(StagedAsset a, NestedObject.Nestable record) {
        String aasRef = (String) record.get('Source_Reference__c');
        if(aasRef == null) {
            aasRef = record.Id;
        }
        a.AssetActions[0].AssetActionSources.add(new AssetActionSource(
            ExternalReference = aasRef,
            ExternalReferenceDataSource = 'Legacy Systems - Business Central'
        ));
        if(record.Id != null) {
            a.sourceIds.add(record.Id);
            a.set('Revision__c', a.sourceIds.size());
        }
    }

    public static void updateGoLiveDate(StagedAsset a, NestedObject.Nestable record) {
        Date currentDate = (Date) a.get('Go_Live_Date__c');
        Date recDate = (Date) record.get('Original_Start_Date__c');

        if(recDate < currentDate) {
            a.set('Go_Live_Date__c', recDate);
        }
    }

    public static void addSerialNumber(StagedAsset a, NestedObject.Nestable record) {
        String sNum = (String) record.get('Serial_Number__c');
        if(sNum != null) {
            System.debug('CREATING S/N RECORD: ' + sNum);
            StagedRecord sNumRec = new StagedRecord(
                new SerialNumber__c(
                    Name = sNum,
                    Unique_Id__c = sNum,
                    Product__c = (Id) record.get('Product__c')
                )
            );
            sNumRec.setLookup('Asset__r', a);
            StagedDatabase.put(sNumRec);
        }
    }

    public static void reflect() {
        // System.debug('REFLECT - DB STATE: ' + StagedDatabase.toJSON());
        List<Asset_Migration_Record__c> updated = new List<Asset_Migration_Record__c>();
        List<Id> sourceIds = new List<Id>();
        for (StagedRecord record : StagedDatabase.all()) {
            if(record.getType() != 'Asset' || record.sourceIds.size() == 0) {
                continue;
            }
            if(((StagedAsset) record).ParentId == null || ((StagedAsset) record).get('Aggregate_Asset__c') == null) {
                // LTC-3783 - only site line assets should be linked to the source record.
                continue;
            }
            // System.debug('REFLECTING ON RECORD: ' + record.toJSON());
            for (Integer i = 0; i < record.sourceIds.size(); i++) {
                String sourceId = record.sourceIds[i];
                if(sourceIds.contains(sourceId)) {
                    continue;
                }
                if(record.inserted) {
                    updated.add(
                        new Asset_Migration_Record__c(
                            Id = sourceId,
                            Asset__c = record.Id,
                            Revision__c = String.valueOf(i + 1)
                        )
                    );
                    sourceIds.add(sourceId);
                } else if (record.error != null) {
                    updated.add(
                        new Asset_Migration_Record__c(
                            Id = sourceId,
                            Error__c = (record.error.getMessage() + '\n' + record.error.getStackTraceString()).abbreviate(32768),
                            Has_Error__c = true
                        )
                    );
                    sourceIds.add(sourceId);
                }
            }
        }
        // System.debug('UPDATED: ' + JSON.serialize(updated));
        Database.update(updated,false);
    }
    /*
    public static void buildRenewals() {
        Datetime cutover = Datetime.now();
        List<Asset> assets = [
            SELECT AssetId
            FROM AssetStatePeriod
            WHERE 
                StartDate <= :cutover AND
                EndDate >= :cutover AND
                Quantity > 0
        ];
    }
    */
    public class DataBlock {
        List<Asset_Migration_Record__c> rows;
        Id accountId;
        Product2 rootProduct;
        public DataBlock(Id accountId, Product2 rootProduct){
            this.accountId = accountId;
            this.rootProduct = rootProduct;
            this.rows = new List<Asset_Migration_Record__c>();
        }
        public void add(Asset_Migration_Record__c row){
            this.rows.add(row);
        }
    }

    public class BatchConfig {
        public Integer blockBatchSize;
        public Integer blockLimitPerCustomer;
        public Integer customerLimit;
        public Integer concurrentBatches;
        public Serenity.BatchConfig assetConfig;

        public BatchConfig() {
            this.blockBatchSize = 1;
            this.blockLimitPerCustomer = null;
            this.customerLimit = null;
            this.concurrentBatches = 2;
            this.assetConfig = new Serenity.BatchConfig();
        }
        public BatchConfig(
            Integer blockBatchSize,
            Integer blockLimitPerCustomer,
            Integer customerLimit,
            Integer concurrentBatches,
            Serenity.BatchConfig assetConfig
        ) {
            this.blockBatchSize = blockBatchSize;
            this.blockLimitPerCustomer = blockLimitPerCustomer;
            this.customerLimit = customerLimit;
            this.concurrentBatches = concurrentBatches;
            if(assetConfig != null) {
                this.assetConfig = assetConfig;
            } else {
                this.assetConfig = new Serenity.BatchConfig();
            }
        }
    }
}