public without sharing class Serenity {

    public static BatchConfig config = new BatchConfig();

    // ENUMs
    private enum DataKeys {
        IS_NEW,
        IS_CHANGED
    }
    public enum AsyncAction {
        Order,
        OrderUpdate,
        CancelOne,
        CancelTree,
        CancelAll,
        EndDate
    }
    public enum AssetType {
        Contract,
        Site
    }

    // PROPERTIES
    //      static members
    public static Boolean runAsync = false;
    private static String sourceAction;
    private static Id internalDeletedAssetAccountId;
    private static Id sourceId;
    private static SerenityFinalizer batchFinalizer;
    public static String namedCredential {
        get {
            return Tranquility.namedCredential;
        }
        set {
            Tranquility.namedCredential = value;
        }
    }
    private static AssignOrderItemToAsset assignOrderItemToAsset = new AssignOrderItemToAsset();
    //      static interface implmentation instances

    public static List<AssetManagementProcessTask> queue;

    // GETTERS
    private static List<String> orderItemExpandFields {
        get {
            return new String[]{
                'Product2.Name',
                'Product2.AssetConversion__c',
                'SBQQ__QuoteLine__r.Asset__c',
                'Order.EffectiveDate',
                'Order.EndDate',
                'Order.AccountId',
                'SBQQ__QuoteLine__r.SBQQ__RequiredBy__r.Asset__c',
                'SBQQ__QuoteLine__r.BundleRoot__r.Asset__c',
                'SBQQ__BundleRoot__r.EndDate',
                'SBQQ__BundleRoot__r.End_Date__c',
                'SBQQ__BundleRoot__r.SBQQ__SubscriptionTerm__c',
                'Asset__r.RootAssetId',
                'Asset__r.Aggregate_Asset__r.RootAssetId'
            };
        }
    }
    public static List<String> assetExpandFields {
        get {
            return new String[]{
                '(SELECT ' + String.join(StagedAssetAction.fields,',') + ' FROM AssetActions)',
                '(SELECT AssetId, Mrr, Amount, Quantity, StartDate, EndDate FROM AssetStatePeriods)',
                'Aggregate_Asset__r.RootAssetId'
            };
        }
    }

    private static Id deletedAssetAccountId {
        get {
            if(internalDeletedAssetAccountId == null) {
                Account a = [SELECT Id FROM Account WHERE Name LIKE '%DELETED ASSET%' LIMIT 1];
                internalDeletedAssetAccountId = a.Id;
            }
            return internalDeletedAssetAccountId;
        }
    }

    // ASYNC ENTRY METHODS
    public static Id AsyncRequest(AsyncAction action, Id inputId, Date inputDate) {
        Integer batchSize = config.blocksPerBatch;
        if(Test.isRunningTest()) {
            // batchSize = queue.size();
            BatchableProcessAssetManagementTasks batchable = new BatchableProcessAssetManagementTasks(action, inputId, inputDate);
            batchSize = ((List<AssetTaskBlock>) batchable.start(null)).size();
            return Database.executeBatch(new BatchableProcessAssetManagementTasks(queue, StagedDatabase.getState(), inputId, action.name(), batchFinalizer), batchSize);
        }
        return Database.executeBatch(new BatchableProcessAssetManagementTasks(action, inputId, inputDate), batchSize);
        // return System.enqueueJob(new AsyncHandler(action, inputId, inputDate));
    }

    // PRIMARY ENTRY METHODS
    public static Id Order(Id orderId) {
        try {
            sourceId = orderId;
            sourceAction = 'Order Activation';
            Order o = [SELECT Id, AccountId FROM Order WHERE Id = :orderId];
            populateDatabase(o.AccountId);
            List<StagedRecord> orderItems = orderItems(o.Id);
            // String dbJson = StagedDatabase.toJSON();
            // System.debug('INITIAL DATA:' + JSON.serialize(orderItems));
            Map<String,NestedObject> roots = new Map<String,NestedObject>();
            Map<String,String>  rootTypes = new Map<String,String>();
            Set<Id> toAggregateRoots = new Set<Id>();
            Set<Id> recontractRoots = new Set<Id>();
            Set<Id> recontractSiteRoots = new Set<Id>();
            Map<Id,Date> recontractDates = new Map<Id,Date>();
            // Loop over order items and store roots -- either bundle id (oi tree to be created as new assets) or root asset id
            // System.debug('Processing ' + orderItems.size() + ' order items...');
            for(StagedRecord oi : orderItems) {
                String rootId = getRootAssetId(oi); // assume it's an existing asset    
                Boolean lineIsRoot = false;
                String type = 'ASSET';
                String parentField = 'SBQQ__QuoteLine__r.SBQQ__RequiredBy__r.Asset__c';

                
                if(rootId == null) {
                    // not an existing asset, class as a bundle
                    rootId = getBundleId(oi);
                    type = 'BUNDLE';
                    parentField = 'SBQQ__RequiredBy__c';
                }
                NestedObject root;
                if(roots.keySet().contains(rootId)) {
                    // rootId already staged in the map--retrieve it
                    root = roots.get(rootId);
                } else {
                    // rootId not yet staged in map--add it
                    if(type == 'BUNDLE') {
                        // System.debug('***BUNDLE | ROOT ID: ' + rootId + '***');
                        if(oi.Id == rootId) {
                            NestedObject newRoot = new NestedObject(oi);
                            root = roots.put(rootId, newRoot);
                            lineIsRoot = true;
                        } else if(!roots.containsKey(rootId)) {
                            NestedObject newRoot = new NestedObject(new StagedRecord(new OrderItem(Id=rootId)));
                            roots.put(rootId, newRoot);
                        }
                    } else {
                        // System.debug('***ASSET | ROOT ID: ' + rootId + '***');
                        System.assertEquals('ASSET', type); // should be the case
                        if((Id) oi.get('Asset__c') == rootId) {
                            // System.debug('\t***ROOT ASSET LINE');
                            // Root asset is actually present on the order
                            root = roots.put(rootId, new NestedObject(oi));
                            lineIsRoot = true;
                        } else {
                            // System.debug('\t***CHILD ASSET LINE');
                            // Root asset not present on the order (normal for an amendment)
                            root = new NestedObject(new StagedAsset());
                            roots.put(rootId, root);
                            // System.debug('INSERTED ROOT:'+root);
                        }
                    }
                    if(lineIsRoot && oi.get('SBQQ__ContractAction__c') == 'Re-contract'){
                        Id contractRootId = (Id) oi.get('Modified_Root_Asset__c');
                        recontractRoots.add(contractRootId);
                        recontractSiteRoots.add(rootId);
                        Date recontractDate = (Date) oi.get('ServiceDate');
                        recontractDates.put(contractRootId, recontractDate);
                        recontractDates.put(rootId, recontractDate);
                    }
                    // Store the root type
                    rootTypes.put(rootId, type);
                    // Only aggregate if the billing & shipping accounts are different
                    if(oi.get('Order.AccountId') != oi.get('SBQQ__ShippingAccount__c')) {
                        toAggregateRoots.add(rootId);
                    }
                }
                if(!lineIsRoot) {
                    // System.debug('\t***ADDING CHILD: ' + oi.get('Asset__c') + '***');
                    NestedObject newNode = root.add(oi, (Id) oi.get(parentField));
                }
            }
            for (String rootId : roots.keySet()) {
                NestedObject root = roots.get(rootId);
                // System.debug('******\n' + JSON.serialize(root));
                switch on rootTypes.get(rootId) {
                    when 'ASSET' {
                        root = NestedObject.assign(
                            getAssetTree(rootId),
                            root,
                            'Id',
                            'Asset__c',
                            'SBQQ__QuoteLine__r.SBQQ__RequiredBy__r.Asset__c',
                            null,
                            assignOrderItemToAsset
                        );
                        roots.put(rootId, root);
                        // System.debug('PRE-PROCESSED ROOT:' + JSON.serialize(root));
                    }
                    when 'BUNDLE' {
                        StagedAsset parent;
                        String parentId = null;
                        for (NestedObject node : root.all()) {
                            StagedAsset a;
                            // Handling for MDQ lines
                            if(((StagedRecord) node.obj).get('SBQQ__SegmentIndex__c') != null) {
                                NestedObject existingNode = root.find(new FindAssetByProductId((Id)((StagedRecord) node.obj).get('Product2Id'), null));
                                if(existingNode != null) {
                                    a = (StagedAsset) existingNode.obj;
                                    // a.AssetStatePeriods.add(createPeriod((StagedRecord) node.obj));
                                }
                            }
                            if(a == null) {
                                a = createAsset((StagedRecord) node.obj);
                            }
                            if(a == null) {
                                continue;
                            }
                            if(node.parentId != null) {
                                if(node.parentId != parentId) {
                                    parent = (StagedAsset) root.findById(node.parentId).obj;
                                    parentId = parent.Id;
                                }
                                a.setLookup('Parent', parent);
                            }
                            node.replaceObject(a);
                            // System.debug('REPLACED NODE:' + JSON.serialize(node));
                            node.setData(DataKeys.IS_NEW.name(), true);
                        }
                    }
                }

                if(recontractSiteRoots.contains(rootId)) {
                    // System.debug('RE-CONTRACT SITE PROCESSING...');
                    // This site is a recontract, so end-date all untouched child assets
                    for (NestedObject node : root.all()) {
                        if(((StagedAsset) node.obj).stagedFor == StagedRecord.StagedAction.NoAction) {
                            // System.debug('END DATING (1): ' + ((StagedAsset) node.obj).Id);
                            EndDate(((StagedAsset) node.obj).Id, Datetime.newInstanceGmt(recontractDates.get(rootId).addDays(-1), Time.newInstance(23,59,59,0)));
                            node.setData(DataKeys.IS_CHANGED.name(), true);
                        }
                    }
                }
                if(Test.isRunningTest()) {
                    System.debug('TO AGG ROOTS: ' + JSON.serialize(toAggregateRoots));
                    System.debug('ROOT ID: ' + rootId);
                }
                rollUpActions(root);
                if(toAggregateRoots.contains(rootId)) {
                    // LTC-2564 - only aggregate when site is different than customer
                    // System.debug('RUNNING AGGREGATE()...');
                    applyActions(aggregate(root, o.AccountId));
                }
                applyActions(root);

            }
            for (Id contractRootId : recontractRoots) {
                // Any site asset children not already touched under the aggregate asset (e.g. because the whole site was removed from the re-contract quote) need to end-dated as well. 
                // System.debug('RE-CONTRACT CUSTOMER ROOT PROCESSING...');
                Set<Id> toProcessRoots = new Set<Id>();
                for (StagedRecord record : StagedDatabase.all()) {
                    if(record.getType() == 'Asset' && record.stagedFor == StagedRecord.StagedAction.NoAction) {
                        if(record.get('Aggregate_Asset__r.RootAssetId') == contractRootId) {
                            // System.debug('END DATING (2): ' + record.Id);
                            EndDate(record.Id, Datetime.newInstanceGmt(recontractDates.get(contractRootId).addDays(-1),Time.newInstance(23,59,59,0)));
                            toProcessRoots.add((Id) record.get('RootAssetId'));
                        }
                    }
                }
                for (Id siteRootId : toProcessRoots) {
                    NestedObject siteRoot = getAssetTree(siteRootId);
                    rollUpActions(siteRoot);
                    if(((StagedAsset) siteRoot.obj).get('Aggregate_Asset__c') != null) {
                        applyActions(aggregate(siteRoot, o.AccountId));
                    }
                    applyActions(siteRoot);
                }
            }
            Id jobId = process();
            AssetManagementLog.logSuccess(orderId, 'Order Activation');
            return jobId;
        } catch (Exception e) {
            AssetManagementLog.logError(e, orderId, 'Order Activation');
            return null;
        }
    }

    public static Id OrderUpdate(Id orderId) {
        try {
            sourceId = orderId;
            sourceAction = 'Order Update';
            Order o = [SELECT Id, AccountId FROM Order WHERE Id = :orderId];
            populateDatabase(o.AccountId);
            List<StagedRecord> orderItems = orderItems(o.Id);
            List<String> rootIds = new List<String>();
            for (StagedRecord oi : orderItems) {
                if(((Boolean) oi.get('Finalised__c')) == true) {
                    continue;
                }
                if(oi.get('SBQQ__Status__c') == 'Completed') {
                    OrderItemUpdate(oi);
                    String rootId = getRootAssetId(oi);
                    if(rootId != null && !rootIds.contains(rootId)) {
                        rootIds.add(rootId);
                    }
                    oi.set('Finalised__c', true);
                } else if (oi.get('SBQQ__Status__c') == 'Deleted') {
                    // TODO: cancel purchased asset
                    oi.set('Finalised__c', true);
                }
            }
             // System.debug('ROOT IDS:' + JSON.serialize(rootIds));
            List<String> contractRootIds = new List<String>();
            for (String rootId : rootIds) {
                NestedObject tree = getAssetTree(rootId);
                rollUpActions(tree);
                // System.debug('ROLLED-UP TREE: ' + JSON.serialize(tree));    

                // System.debug('START CT LINE ACTIONS: ' + JSON.serialize(((StagedAsset) StagedDatabase.get('02i2500000UEXMEAA5')).AssetActions));
                NestedObject aggTree = aggregate(tree, o.AccountId);
                // System.debug('PRE-APPLY CT LINE ACTIONS: ' + JSON.serialize(((StagedAsset) StagedDatabase.get('02i2500000UEXMEAA5')).AssetActions));
                applyActions(aggTree);
                // System.debug('POST CT LINE PERIODS: ' + JSON.serialize(((StagedAsset) StagedDatabase.get('02i2500000UEXMEAA5')).AssetStatePeriods));
                // System.debug('PRE-APPLY: ' + JSON.serialize(tree));
                applyActions(tree);
                // System.debug('POST-APPLY: ' + JSON.serialize(tree));
                /*
                String contractRootId = aggTree.obj.Id;
                if(!contractRootIds.contains(contractRootId)) {
                    contractRootIds.add(contractRootId);
                }
                */
                // applyActions(aggTree);
            }
            // System.debug('FINAL CT LINE ACTIONS: ' + JSON.serialize(((StagedAsset) StagedDatabase.get('02i2500000UEXMEAA5')).AssetActions));
            /*
            for (String contractRootId : contractRootIds) {
                applyActions(getAssetTree(contractRootId));
            }
            */
            Id jobId = process();
            AssetManagementLog.logSuccess(sourceId, sourceAction);
            return jobId;
        } catch (Exception e) {
            AssetManagementLog.logError(e, sourceId, sourceAction);
            return null;
        }
    }

    public static Id CancelAll(Id accountId) {
        sourceAction = 'Cancel all';
        sourceId = accountId;
        StagedDatabase.addWhere('Asset', 'AccountId = \'' + accountid + '\' OR Aggregate_Asset__r.AccountId = \'' + accountId + '\'', assetExpandFields, StagedAsset.class);
        StagedDatabase.addWhere('OrderItem', 'Asset__r.AccountId = \'' + accountId + '\' OR Asset__r.Aggregate_Asset__r.AccountId = \'' + accountId + '\'', orderItemExpandFields);
        for(StagedRecord record : StagedDatabase.all()) {
            switch on record.getType() {
                when 'Asset' {
                    record.set('AccountId', deletedAssetAccountId);
                    record.set('Status', 'Cancelled');
                }
                when 'OrderItem' {
                    record.set('Asset__c', null);
                }
            }
        }
        return process();
    }

    public static void EndDate(Id assetId, Datetime asOf) {
        sourceId = assetId;
        sourceAction = 'Cancel Asset';
        StagedAsset a = (StagedAsset) StagedDatabase.get(assetId);
        if(a == null) {
            StagedDatabase.addWhere('Asset', 'Id = \'' + assetId + '\'',assetExpandFields, StagedAsset.class);
            a = (StagedAsset) StagedDatabase.get(assetId);
        }
        // System.debug('CANCELLING AS OF: ' + asOf);
        // System.debug(JSON.serialize(a));
        a.Status = 'Cancelled';
        Decimal mrr = 0.0;
        Decimal quantity = 0.0;
        Decimal amount = 0.0;
        Boolean hasPeriod = false;
        Date assetEnd;
        for (StagedAssetStatePeriod asp : a.AssetStatePeriods) {
            if(assetEnd == null || assetEnd < asp.EndDate.dateGmt()) {
                assetEnd = asp.EndDate.dateGmt();
            }
            if(asp.StartDate <= asOf && asp.EndDate > asOf) {
                hasPeriod = true;
                asp.EndDate = asOf;
                amount -= asp.Amount;
                mrr = asp.Mrr;
                quantity = asp.Quantity;
            } else if(asp.StartDate > asOf) {
                amount += asp.Amount;
            }
            asp.touch();
        }
        System.assert(hasPeriod, 'Cannot end date asset outside of lifecycle');
        StagedAssetAction aa = new StagedAssetAction();
        aa.ActionDate = Datetime.now();
        aa.MrrChange = -1.0 * mrr;
        aa.QuantityChange = -1.0 * quantity;
        aa.CategoryEnum = StagedAssetAction.Category.Cancellations;
        aa.effectiveStartDate = asOf.dateGmt().addDays(1);
        aa.effectiveEndDate = assetEnd;
        a.AssetActions.add(aa);
        aa.rollUp = false;
    }

    public static Id CancelOne(Id assetId) {
        return CancelOne(assetId, true);
    }

    public static Id CancelOne(Id assetId, Boolean runProc) {
        if(sourceId == null) {
            sourceId = assetId;
        }
        if(sourceAction == null) {
            sourceAction = 'Cancel Asset';
        }
        StagedAsset a = (StagedAsset) StagedDatabase.get(assetId);
        if(a == null) {
            StagedDatabase.addWhere('Asset', 'Id = \'' + assetId + '\'',assetExpandFields, StagedAsset.class);
            a = (StagedAsset) StagedDatabase.get(assetId);
        }
        a.AccountId = deletedAssetAccountId;
        a.Status = 'Cancelled';
        if(runProc) {
            return process();
        }
        return null;
    }

    public static Id CancelTree(Id assetId) {
        try {
            sourceId = assetId;
            sourceAction = 'Cancel Asset';
            StagedDatabase.addWhere(
                'Asset', 
                'RootAssetId = \'' + assetId + '\' OR Aggregate_Asset__r.RootAssetId = \'' + assetId + '\'',
                assetExpandFields, 
                StagedAsset.class
            );
            StagedDatabase.addWhere(
                'OrderItem',
                'Asset__r.RootAssetId = \'' + assetId + '\' OR Asset__r.Aggregate_Asset__r.RootAssetId = \'' + assetId + '\'',
                orderItemExpandFields
            );
            for (StagedRecord record : StagedDatabase.all()) {
                switch on record.getType() {
                    when 'Asset' {
                        ((StagedAsset) record).AccountId = deletedAssetAccountId;
                        ((StagedAsset) record).Status = 'Cancelled';
                    }
                    when 'OrderItem' {
                        record.set('Asset__c', null);
                    }
                }
            }
            Id jobId = process();
            AssetManagementLog.logSuccess(assetId, 'Cancel Tree');
            return jobId;
        } catch (Exception e) {
            AssetManagementLog.logError(e, assetId, 'Cancel Tree');
            return null;
        }
    }

    // ORCHESTRATION & DATA
    public static List<AssetTaskBlock> buildBlocks(List<AssetManagementProcessTask> tasks) {
        List<AssetManagementProcessTask> dmlTasks = new List<AssetManagementProcessTask>();
        List<List<AssetManagementProcessTask>> taskLists = new List<List<AssetManagementProcessTask>>();
        for (Integer idx = 0; idx < config.blockConfigs.size(); idx++) {
            taskLists.add(new List<AssetManagementProcessTask>());
        }
        if(tasks == null) {
            AssetManagementLog.logError(new SerenityException('No tasks available for processing.'), sourceId, sourceAction);
            return new List<AssetTaskBlock>();
        }
        for (AssetManagementProcessTask task : tasks) {
            // Sort tasks based on thresholds defined. 
            switch on task.type {
                when CALLOUT {
                    Integer listIdx = -1;
                    for (Integer idx = 0; idx < config.blockConfigs.size(); idx++) {
                        if(task.request.complexity < config.blockConfigs[idx].threshold || config.blockConfigs[idx].threshold == null) {
                            listIdx = idx;
                            break;
                        }
                    }
                    List<AssetManagementProcessTask> taskList = taskLists.get(listIdx);
                    taskList.add(task);
                }
                when DML {
                    dmlTasks.add(task);
                }
            }
        }

        // System.debug('TASK LISTS:' + JSON.serialize(taskLists));

        Integer totalTaskCount = 0;
        List<AssetTaskBlock> blocks = new List<AssetTaskBlock>();
        for (Integer z = 0; z < taskLists.size(); z++) {
            List<AssetManagementProcessTask> taskList = taskLists.get(z);
            Boolean hasMore = true;
            for (Integer i = 0; ((i * config.blockConfigs[z].taskSize) < taskList.size()) && hasMore; i++) {
                List<AssetManagementProcessTask> blockTasks = new List<AssetManagementProcessTask>();
                for (Integer j = 0; j < config.blockConfigs[z].taskSize; j++) {
                    Integer idx = i * config.blockConfigs[z].taskSize + j;
                    if(idx < taskList.size()) {
                        blockTasks.add(taskList[idx]);
                    } else {
                        hasMore = false;
                        break;
                    }
                }
                blocks.add(new AssetTaskBlock(blockTasks));
                totalTaskCount += blockTasks.size();
            }
        }
        blocks.add(new AssetTaskBlock(dmlTasks));
        totalTaskCount += dmlTasks.size();
        System.assertEquals(tasks.size(), totalTaskCount, 'Mismatched total task count.');
        return blocks;
    }
    public static Id process(SerenityFinalizer finalizer) {
        batchFinalizer = finalizer;
        return process();
    }
    public static Id process() {
        return process(runAsync);
    }
    private static Id process(Boolean isAsync) {
        queue = new List<AssetManagementProcessTask>();
        // String finalData = StagedDatabase.toJSON();
        // System.debug('PROCESSED DATA:\n' + StagedDatabase.toJSON());
        Set<String> assetsToUpdate = new Set<String>();
        Set<String> orderItemsToUpdate = new Set<String>();
        Set<String> otherObjsToInsert = new Set<String>();
        Set<String> otherObjsToUpdate = new Set<String>();
        Set<String> idsToUpdate = new Set<String>();
        for(StagedRecord record : StagedDatabase.all()){
            switch on record.getType() {
                when 'Asset' {
                    switch on record.stagedFor {
                        when UpdateAction {
                            idsToUpdate.addAll(queueAssetUpdate((StagedAsset) record));
                        }
                        when InsertAction {
                            idsToUpdate.addAll(queueAssetInsert((StagedAsset) record));
                        }
                    }
                }
                when 'OrderItem' {
                    switch on record.stagedFor {
                        when UpdateAction {
                            orderItemsToUpdate.add(record.Id);
                        }
                    }
                }
                when 'SBQQ__QuoteLine__c' {
                    // do nothing
                }
                when 'AssetAction' {
                    // do nothing
                }
                when 'AssetStatePeriod' {
                    // do nothing
                }
                when 'AssetActionSource' {
                    // do nothing
                }
                when else {
                    switch on record.stagedFor {
                        when InsertAction {
                            otherObjsToInsert.add(record.Id);
                        }
                        when UpdateAction {
                            otherObjsToUpdate.add(record.Id);
                        }
                    }
                }
            }
        }
        if(idsToUpdate.size() > 0) {
            for (String idToUpdate : idsToUpdate) {
                if(!PWUtils.isId(idToUpdate)) {
                    assetsToUpdate.add(idToUpdate);
                } else {
                    SObjectType objType = Id.valueOf(idToUpdate).getSobjectType();
                    if(objType == PWUtils.getSObjectType('Asset')) {
                        assetsToUpdate.add(idToUpdate);
                    } else if(objType == PWUtils.getSObjectType('OrderItem')) {
                        orderItemsToUpdate.add(idToUpdate);
                    } else {
                        throw new SerenityException('Updated id (' + idToUpdate + ') does not match expected types (\'Asset\', \'OrderItem\')');
                    }
                }
            }
        }
        if(assetsToUpdate.size() > 0) {
            AssetManagementProcessTask updateAssetTask = new AssetManagementProcessTask(
                PWUtils.DMLOperation.DML_UPDATE,
                new SObject[]{}
            );
            updateAssetTask.before(new RetrieveStagedRecords(assetsToUpdate));
            queue.add(updateAssetTask);
        }
        if(orderItemsToUpdate.size() > 0) {
            AssetManagementProcessTask updateOrderItemTask = new AssetManagementProcessTask(
                PWUtils.DMLOperation.DML_UPDATE,
                new SObject[]{}
            );
            updateOrderItemTask.before(new RetrieveStagedRecords(orderItemsToUpdate));
            queue.add(updateOrderItemTask);
        }   
        if(otherObjsToInsert.size() > 0) {
            AssetManagementProcessTask insertObjsTask = new AssetManagementProcessTask(
                PWUtils.DMLOperation.DML_INSERT,
                new SObject[]{}
            );
            insertObjsTask.before(new RetrieveStagedRecords(otherObjsToInsert));
            queue.add(insertObjsTask);
        }
        if(otherObjsToUpdate.size() > 0) {
            AssetManagementProcessTask updateObjsTask = new AssetManagementProcessTask(
                PWUtils.DMLOperation.DML_UPDATE,
                new SObject[]{}
            );
            updateObjsTask.before(new RetrieveStagedRecords(otherObjsToUpdate));
            queue.add(updateObjsTask);
        }
        // System.debug('***FINAL TASK QUEUE***\n' + JSON.serialize(queue));
        // if(USE_BATCH) {
        //     queue = AssetManagementProcessTask.batchify(queue);
        // }
        if(isAsync) {
            return null;
        }
        // if(Test.isRunningTest()) {
        //     for (AssetTaskBlock block : buildBlocks(queue)) {
        //         System.debug('TASK BLOCK: ' + JSON.serialize(block));
        //         block.process();
        //     }
        //     if(batchFinalizer != null) {
        //         batchFinalizer.execute();
        //     }
        //     return null;
        // } else {
            Integer batchSize = config.blocksPerBatch;
            if(Test.isRunningTest()) {
                System.assertNotEquals(0, queue.size(), 'No tasks available for processing');
                batchSize = queue.size();
                System.debug('***TASKS***: ' + JSON.serialize(queue));
            }
            return Database.executeBatch(new BatchableProcessAssetManagementTasks(queue, StagedDatabase.getState(), sourceId, sourceAction, batchFinalizer), batchSize);
        // }
    }

    private static Set<String> queueAssetUpdate(StagedAsset record) {
        Set<String> updateIds = new Set<String>();
        // Compare existing record to staged record and generate Tranquility request
        if(record.get('Status') != 'Cancelled' && record.hasCALMUpdate() && !record.isValidForAction()) {
            if(Test.isRunningTest()) {
                System.debug('INVALID RECORD: ' + JSON.serialize(record));
            }
            StagedAsset newAsset = StagedAsset.copy(record);
            newAsset.Id = null;
            newAsset.set('AssetNumberOverride__c', record.get('AssetNumber__c'));
            newAsset.setLookup('Parent', record.getLookup('Parent'));
            newAsset.setLookup('Aggregate_Asset__r', record.getLookup('Aggregate_Asset__r'));
            newAsset.initiate();
            StagedDatabase.put(newAsset);
            updateIds.addAll(StagedDatabase.rePoint(record.Id, newAsset.Id));
            // System.debug('CANCEL AND REPLACING: ' + record.Id + ' -> ' + newAsset.Id);
            record.set('Status', 'Cancelled');
            record.set('AccountId', deletedAssetAccountId);
            record.setLookup('Aggregate_Asset__r', null);
            record.setLookup('Parent', null);
            record.AssetStatePeriods = StagedAssetStatePeriod.fromList(((Asset) record.getRecord()).AssetStatePeriods);
            updateIds.addAll(queueAssetInsert(newAsset));
        }
        if(record.get('Status') == 'Cancelled' && record.changes.containsKey('Status')) {
            Tranquility.CancelAssetRequest req = new Tranquility.CancelAssetRequest(record.Id);
            Tranquility.AssetActionInput aa;
            for (StagedAssetAction action : record.AssetActions) {
                if(action.stagedFor == StagedRecord.StagedAction.InsertAction && action.CategoryEnum == StagedAssetAction.Category.Cancellations) {
                    aa = new Tranquility.AssetActionInput(action);
                }
            }
            if(aa == null) {
                aa = new Tranquility.AssetActionInput();
                Datetime cancelDate = Datetime.now();
                // System.debug('EXISTING ASSET ACTIONS: ' + JSON.serialize(record.AssetActions));
                for(StagedAssetAction action : record.AssetActions) {
                    if(action.CategoryEnum == StagedAssetAction.Category.Cancellations) {
                        return updateIds; // already cancelled
                    }
                    if(action.ActionDate >= cancelDate) {
                        cancelDate = action.ActionDate.addDays(1);
                    }
                }
                Double currentAmount = (Double) record.get('CurrentAmount');
                Double currentMrr = (Double) record.get('CurrentMrr');
                Double currentQuantity = (Double) record.get('CurrentQuantity');
                if(currentAmount == null) {
                    currentAmount = 0.0;
                }
                if(currentMrr == null) {
                    currentMrr = 0.0;
                }
                if (currentQuantity == null) {
                    currentQuantity = 0.0;
                }
                aa.mrrChange = -1.0 * currentMrr;
                aa.amount = -1.0 * currentAmount;
                aa.actionDate = cancelDate;
                aa.category = 'Cancellations';
                aa.quantityChange = -1.0 * currentQuantity;
            }
            
            req.assetAction = aa;
            Tranquility.AssetStatePeriodInput asp;
            Tranquility.AssetStatePeriodInput fallbackAsp;
            for (StagedAssetStatePeriod period : record.AssetStatePeriods) {
                if(period.stagedFor != StagedRecord.StagedAction.NoAction) {
                    asp = new Tranquility.AssetStatePeriodInput(period);
                    break;
                } else if (fallbackAsp == null) {
                    fallbackAsp = new Tranquility.AssetStatePeriodInput(period);
                }
            }
            if(asp == null) {
                asp = new Tranquility.AssetStatePeriodInput();
                asp.startDate = record.LifecycleStartDate;
                if(asp.startDate == null && fallbackAsp != null) {
                    asp.startDate = fallbackAsp.startDate;
                }
                asp.endDate = record.LifecycleEndDate;
                if(asp.endDate == null) {
                    asp.endDate = Datetime.newInstanceGmt(Date.today(), Time.newInstance(23, 59, 59, 0));
                }
                if(asp.endDate < asp.startDate) {
                    asp.endDate = Datetime.newInstanceGmt(asp.startDate.dateGmt(), Time.newInstance(23, 59, 59, 0));
                }
                asp.mrr = (Double) record.get('CurrentMrr');
                asp.quantity = (Double) record.get('CurrentQuantity');
                asp.amount = (Double) record.get('CurrentAmount');
            }
            req.assetStatePeriod = asp;
            queue.add(req.generateTask());
        } else {
            Boolean hasAction = false;
            for (StagedAssetAction aa : record.AssetActions) {
                if(aa.stagedFor != StagedRecord.StagedAction.NoAction) {
                    hasAction = true;
                    break;
                }
            }
            if(hasAction) {
                Tranquility.ChangeAssetRequest req = new Tranquility.ChangeAssetRequest(record);
                queue.add(req.generateTask());
            }
        }
        updateIds.add(record.Id);
        return updateIds;
    }

    private static List<String> queueAssetInsert(StagedAsset record) {
        List<String> updateIds = new List<String>();
        Tranquility.GenerateAssetRequest req = new Tranquility.GenerateAssetRequest(record);
        List<AssetManagementProcessTask> changeTasks = new List<AssetManagementProcessTask>();
        Tranquility.UpsertAssetRequest baseReq = req;
        while (baseReq.aspOverflow != null) {
            if(record.Id == null) {
                System.debug('NULL ID RECORD');
                System.debug(record);
                throw new SerenityException('Aborted');
            }
            Tranquility.ChangeAssetRequest changeReq = new Tranquility.ChangeAssetRequest(baseReq, null);
            // This is purposely left as a blank request (which would fail) but will be replaced in PreSubsequentChangeTask with a real requst after an id is established.
            AssetManagementProcessTask changeTask = new AssetManagementProcessTask(new Tranquility.SerializableRequest());
            changeTask.before(new PreSubsequentChangeTask(record.Id, baseReq));
            changeTask.after(new AfterAssetInsertHook(record.Id));
            changeTasks.add(changeTask);
            baseReq = changeReq;
        }
        AssetManagementProcessTask task = req.generateTask();
        task.after(new AfterAssetInsertHook(record.Id));
        queue.add(task);
        if(changeTasks.size() > 0) {
            queue.addAll(changeTasks);
        }
        updateIds.add(record.Id);
        return updateIds;
    }

    private static List<StagedRecord> orderItems(Id orderId) {
        StagedDatabase.addWhere(
            'SBQQ__QuoteLine__c',
            'Id IN (SELECT SBQQ__QuoteLine__c FROM OrderItem WHERE OrderId = \'' + orderId + '\')', 
            new String[]{}
        );
        return StagedDatabase.addWhere(
            'OrderItem',
            'OrderId = \'' + orderId + '\' AND Product2.AssetConversion__c != null ORDER BY SBQQ__BundleRoot__c',
            orderItemExpandFields
        );
    }

    private static NestedObject getAssetTree(String rootId) {
        rootId = StagedDatabase.get(rootId).Id; // in case the id has been re-pointed.
        List<StagedRecord> flatInput = StagedDatabase.query(new FindTreeForId(rootId));
        NestedObject tree = new NestedObject(
            StagedDatabase.query(new FindTreeForId(rootId)),
            'Id',
            'ParentId'
        );
        // System.debug('***TREE***:   '+JSON.serialize(tree));
        for (NestedObject node : tree.all()) {
            if(node.obj == null){
                continue;
            }
            switch on ((StagedRecord) node.obj).stagedFor {
                when InsertAction {
                    node.setData(DataKeys.IS_NEW.name(),true);
                }
                when UpdateAction {
                    node.setData(DataKeys.IS_CHANGED.name(),true);
                }
            }
        }
        return tree;
    }

    private static void populateDatabase(Id accountId) {
        StagedDatabase.addWhere(
            'Asset',
            'AccountId = \'' + accountId + '\' OR Aggregate_Asset__r.AccountId = \'' + accountId + '\'',
            assetExpandFields,
            StagedAsset.class
        );
    }

    // BUSINESS LOGIC
    public static void OrderItemUpdate(Id orderItemId) {
        orderItemUpdate(StagedDatabase.get(orderItemId));
    }

    public static void OrderItemUpdate(StagedRecord orderItem) {
        // StagedRecord orderItem = StagedDatabase.add(orderItemId, orderItemExpandFields);
        // StagedAsset asset = (StagedAsset) StagedDatabase.add((Id) orderItem.get('Asset__c'), assetExpandFields, StagedAsset.class);
        // System.debug('UPDATING ORDER ITEM: ' + JSON.serialize(orderItem));
        StagedAsset asset = (StagedAsset) StagedDatabase.get((Id) orderItem.get('Asset__c'));
        if(asset == null) {
            return;
        }
        Date initialStart = (Date) orderItem.get('ServiceDate'); // 2024-01-30
        Date finalStart = (Date) orderItem.get('Start_Date__c'); // 2024-03-
        Date finalEnd;
        if(orderItem.get('SBQQ__ChargeType__c') != 'One-Time') {
            finalEnd = (Date) orderItem.get('End_Date__c');
            if(finalEnd == null) {
                finalEnd = (Date) orderItem.get('SBQQ__BundleRoot__r.EndDate');
            }
        }

        StagedAssetAction aa = createAction(orderItem); // new StagedAssetAction();
        if(initialStart != finalStart) {
            StagedAssetAction squash = createAction(orderItem);
            squash.effectiveStartDate = (Date) orderItem.get('ServiceDate'); // Quoted start date
            if(orderItem.get('SBQQ__ChargeType__c') == 'One-Time') {
                squash.effectiveEndDate = null;
            } else {
                squash.effectiveEndDate = (Date) orderItem.get('EndDate'); // Quoted end date
            }
            if(squash.recurringAmount != null) {
                squash.recurringAmount = -1.0 * squash.recurringAmount;
            }
            if(squash.oneTimeAmount != null) {
                squash.oneTimeAmount = -1.0 * squash.oneTimeAmount;
            }
            squash.QuantityChange = -1.0 * squash.QuantityChange;
            squash.CategoryEnum = StagedAssetAction.Category.IGNORE;
            squash.ActionDate = Datetime.now();
            asset.AssetActions.add(squash);
        } else {
            aa.QuantityChange = 0.0;
            aa.oneTimeAmount = 0.0;
            aa.recurringAmount = 0.0;
        }
        // aa.ActionDate = Datetime.now();
        // aa.MrrChange = 0.0;
        // aa.Amount = 0.0;
        // aa.QuantityChange = 0.0;
        aa.CategoryEnum = StagedAssetAction.Category.Other;
        aa.AssetActionSources.add(createSource(orderItem));
        aa.effectiveStartDate = finalStart;
        aa.effectiveEndDate = finalEnd;
        asset.AssetActions.add(aa);
        if(orderItem.get('SBQQ__Status__c') == 'Completed') {
            asset.Status = 'Installed';
            asset.set('Go_Live_Date__c', orderItem.get('Start_Date__c'));
        }
        asset.touch();
    }

    public static Id getBundleId(StagedRecord oi) {
        Id bundleId = (Id) oi.get('SBQQ__BundleRoot__c');
        if(bundleId == null) {
            bundleId = oi.Id;
        }
        return bundleId;
}

    private static String getRootAssetId(StagedRecord oi) {
        if(oi.get('Asset__c') != null){
            StagedAsset oiAsset = (StagedAsset) oi.getLookup('Asset__r');
            if(oiAsset != null) {
                return oiAsset.RootAssetId;
            } else {
                System.assert(false, 'Asset not found for id: ' + oi.get('Asset__c') + ' - ' + JSON.serialize(oi));
            }
        }
        Id rootAssetId = (Id) oi.get('SBQQ__QuoteLine__r.BundleRoot__r.Asset__c');
        return rootAssetId;
    }

    public static void applyActions(NestedObject tree) {
        // System.debug('APPLYING ACTIONS TO TREE: ' + JSON.serialize(tree));
        for (NestedObject node : tree.all()) {
            applyActions((StagedAsset) node.obj);
        }
    }

    public static void applyActions(StagedAsset asset) {
        StagedAssetAction combinedAction;
        List<Integer> combinedIdxs = new List<Integer>();
        System.debug('*** APPLYING ACTIONS: ' + asset.Id + ' / ' + asset.Product2Id + ' ***');
        System.debug('\tACTIONS: ' + JSON.serialize(asset.AssetActions));
        for (Integer actionIdx = 0; actionIdx < asset.AssetActions.size(); actionIdx++) {
            StagedAssetAction action = asset.AssetActions[actionIdx];
            if(action.stagedFor != StagedRecord.StagedAction.InsertAction) {
                // actions.add(aa);
                continue;
            }
            combinedIdxs.add(actionIdx);
            if(combinedAction == null) {
                combinedAction = action.clone();
                combinedAction.effectiveStartDate = null;
                combinedAction.effectiveEndDate = null;
                if(combinedAction.CategoryEnum == StagedAssetAction.Category.IGNORE) {
                    combinedAction.CategoryEnum = StagedAssetAction.Category.Other;
                }
            } else {
                // System.debug('COMB ACTION: ' + JSON.serialize(combinedAction));
                // System.debug('ACTION: ' + JSON.serialize(action));
                combinedAction.Amount += action.Amount;
                if(combinedAction.MrrChange == null) {
                    combinedAction.MrrChange = action.MrrChange;
                } else if(action.MrrChange != null) {
                    combinedAction.MrrChange += action.MrrChange;
                }
                if(combinedAction.QuantityChange == null) {
                    combinedAction.QuantityChange = action.QuantityChange;
                } else if(action.QuantityChange != null) {
                    combinedAction.QuantityChange += action.QuantityChange;
                }
                combinedAction.AssetActionSources.addAll(action.AssetActionSources);
            }
            if(action.applied) {
                continue;
            }
            // System.debug('\tACTION:' + JSON.serialize(action));
            // if(actions.size() == 0) {
            //     return;
            // }
            // for (StagedAssetAction action : actions) {
            List<StagedAssetStatePeriod> newPeriods = new List<StagedAssetStatePeriod>();
            Boolean leftPeriod = false; // If true, the period to the left of the action start exists and is already "set"
            Boolean rightPeriod = false; // if true, the period to the right of the action end exists and is already "set"
            Boolean aspWhollyContained = false; // ???
            Date leftEnd;
            Date rightStart;
            System.debug('\tASPS: ' + JSON.serialize(asset.AssetStatePeriods));
            for (Integer idx = 0; idx < asset.AssetStatePeriods.size(); idx++) {
                StagedAssetStatePeriod asp = asset.AssetStatePeriods[idx];
                // System.debug('\tASP:' + JSON.serialize(asp));
                // System.debug('ASP ID: ' + asp.Id);
                if(asp.StartDate.dateGmt() < action.effectiveStartDate && (asp.EndDate == null || asp.EndDate.dateGmt() >= action.effectiveStartDate)) {
                    // ASP is split by action start
                    // System.debug('\t\tCASE 1');
                    leftPeriod = true;
                    if(asp.EndDate != null && (leftEnd == null || asp.EndDate > leftEnd)) {
                        leftEnd = asp.EndDate.dateGmt();
                    }
                    if((asp.EndDate == null && action.effectiveEndDate == null) || asp.EndDate.dateGmt() == action.effectiveEndDate) {
                        rightPeriod = true;
                    }

                    // Create new period for back of existing ASP
                    StagedAssetStatePeriod newPd = new StagedAssetStatePeriod();
                    newPd.StartDate = action.effectiveStartDate;
                    newPd.EndDate = asp.EndDate;
                    newPd.Mrr = asp.Mrr;
                    newPd.Quantity = asp.Quantity;
                    newPd.oneTimeAmount = 0;

                    // Apply changes: Recurring to go-forward period; one-times to left (existing) period
                    newPd.applyAmountChange(action.oneTimeAmount, StagedAssetStatePeriod.ChangeType.OneTime);
                    // ***
                    if(action.recurringAmount != null) {
                        newPd.applyAmountChange(action.getRecurringPart(newPd.StartDate.dateGmt(), newPd.EndDate.dateGmt()), StagedAssetStatePeriod.ChangeType.Recurring);
                    }
                    newPd.Quantity += action.QuantityChange;

                    // Updating end date will automatically update the amount and keep existing Mrr.
                    asp.EndDate = Datetime.newInstanceGmt(action.effectiveStartDate.addDays(-1), Time.newInstance(23,59,59,0));

                    if(newPd.Quantity == 0 && newPd.oneTimeAmount == 0 && newPd.Mrr == 0 && idx == (asset.AssetStatePeriods.size() -1)) {
                        // current asp is last period and this is a "zeroed-out" period. Thus don't add it at all.
                        // System.debug('\t\t\t****NOT ADDING NEW PERIOD****');
                        continue;
                    } 
                    // else {
                    //     System.debug('\t\t\t*** ADDING NEW PERIOD *** ' + JSON.serialize(newPd));
                    // }

                    newPeriods.add(newPd);
                } else if (
                    asp.StartDate.dateGmt() >= action.effectiveStartDate && // start dates aligned
                        (
                            (asp.EndDate == null && action.effectiveEndDate == null) || // both end dates are null
                            asp.EndDate != null && ( // asp has an end date and...
                                action.effectiveEndDate == null || asp.EndDate.dateGmt() <= action.effectiveEndDate // end dates are aligned
                            )
                        )
                    ) {
                    // System.debug('\t\tCASE 2');
                    // ASP is wholly contained within action
                    aspWhollyContained = true;
                    if(asp.StartDate.dateGmt() == action.effectiveStartDate) {
                        leftPeriod = true;
                    } else if(rightStart == null || asp.StartDate.dateGmt() < rightStart) {
                        rightStart = asp.StartDate.dateGmt();    
                    }
                    if(asp.EndDate == null || asp.EndDate.dateGmt() == action.effectiveEndDate) {
                        rightPeriod = true;
                    } else  if(leftEnd == null || asp.EndDate.dateGmt() > leftEnd) {
                        leftEnd = asp.EndDate.dateGmt();
                    }
                    // Apply changes: Only apply recurring change to existing asp based on existing dates
                    if(action.recurringAmount != null && action.recurringAmount != 0) {
                        asp.applyAmountChange(action.getRecurringPart(asp.StartDate.dateGmt(), asp.EndDate.dateGmt()), StagedAssetStatePeriod.ChangeType.Recurring);
                    }
                    if(asp.StartDate.dateGmt() == action.effectiveStartDate) {
                        // Apply ot changes
                        asp.applyAmountChange(action.oneTimeAmount, StagedAssetStatePeriod.ChangeType.OneTime);
                    }
                    asp.Quantity += action.QuantityChange;
                } else if (action.effectiveEndDate != null && asp.StartDate.dateGmt() <= action.effectiveEndDate && (asp.EndDate == null || asp.EndDate.dateGmt() > action.effectiveEndDate)) {
                    // System.debug('\t\tCASE 3');
                    // ASP is split by action end
                    leftPeriod = asp.StartDate.dateGmt() == action.effectiveStartDate;
                    rightPeriod = true;
                    if(rightStart == null || asp.StartDate < rightStart) {
                        rightStart = asp.StartDate.dateGmt();
                    }

                    StagedAssetStatePeriod newPd = new StagedAssetStatePeriod();
                    newPd.StartDate = Datetime.newInstanceGmt(action.effectiveEndDate.addDays(1),Time.newInstance(0,0,0,0));
                    newPd.EndDate = asp.EndDate;
                    newPd.Mrr = asp.Mrr;
                    newPd.Quantity = asp.Quantity;
                    newPd.oneTimeAmount = 0;

                    // Apply changes: Only apply recurring change to new period; left period should receive OT changes
                    if(action.effectiveEndDate != null) {
                        asp.endDate = Datetime.newInstanceGmt(action.effectiveEndDate, Time.newInstance(23, 59, 59, 0));
                    }
                    asp.applyAmountChange(action.getRecurringPart(asp.StartDate.dateGmt(), asp.EndDate.dateGmt()), StagedAssetStatePeriod.ChangeType.Recurring);
                    asp.Quantity += action.QuantityChange;

                    newPeriods.add(newPd);
                } else if (asp.StartDate.dateGmt() < action.effectiveStartDate && action.effectiveEndDate != null && (asp.EndDate == null || asp.EndDate.dateGmt() > action.effectiveEndDate)) {
                    // System.debug('\t\tCASE 4');
                    // action is wholly contained within ASP
                    leftPeriod = true;
                    rightPeriod = true;

                    StagedAssetStatePeriod actionPd = new StagedAssetStatePeriod();
                    actionPd.StartDate = Datetime.newInstanceGmt(action.effectiveStartDate, Time.newInstance(0,0,0,0));
                    if(action.effectiveEndDate != null) {
                        actionPd.EndDate = Datetime.newInstanceGmt(action.effectiveEndDate, Time.newInstance(23,59,59,0));
                    }
                    actionPd.Mrr = asp.Mrr;
                    actionPd.Quantity = asp.Quantity;
                    actionPd.oneTimeAmount = 0;

                    StagedAssetStatePeriod postActionPd = new StagedAssetStatePeriod();
                    postActionPd.StartDate = Datetime.newInstanceGmt(action.effectiveEndDate.addDays(1), Time.newInstance(0,0,0,0));
                    postActionPd.EndDate = asp.EndDate;
                    postActionPd.Mrr = asp.Mrr;
                    postActionPd.Quantity = asp.Quantity;
                    postActionPd.oneTimeAmount = 0;

                    asp.EndDate = Datetime.newInstanceGmt(action.effectiveStartDate.addDays(-1), Time.newInstance(23,59,59,0));
                    asp.applyAmountChange(action.oneTimeAmount, StagedAssetStatePeriod.ChangeType.OneTime);
                    actionPd.applyAmountChange(action.recurringAmount, StagedAssetStatePeriod.ChangeType.Recurring);
                    actionPd.Quantity += action.QuantityChange;

                    newPeriods.add(actionPd);
                    newPeriods.add(postActionPd);
                }
            }
            if(!leftPeriod && !rightPeriod && !aspWhollyContained) {
                // System.debug('\t\tCASE 5');
                StagedAssetStatePeriod asp = new StagedAssetStatePeriod();
                asp.StartDate = Datetime.newInstanceGmt(action.effectiveStartDate, Time.newInstance(0,0,0,0));
                if(action.effectiveEndDate != null) {
                    asp.EndDate = Datetime.newInstanceGmt(action.effectiveEndDate, Time.newInstance(23,59,59,0));
                }
                asp.oneTimeAmount = action.oneTimeAmount;
                if(action.recurringAmount != null) {
                    asp.Mrr = PWUtils.unprorate(
                        action.recurringAmount,
                        action.effectiveStartDate,
                        action.effectiveEndDate,
                        PWUtils.ProrationMethod.MONTHLY_DAILY,
                        PWUtils.Period.MONTH
                    );
                }
                asp.Quantity = action.QuantityChange;
                newPeriods.add(asp);
            } else {
                if(!leftPeriod) {
                    // There is a gap between action start and start of left-most current period; create new left period from action start -> right start
                    // System.debug('\t\tCASE 6');
                    StagedAssetStatePeriod asp = new StagedAssetStatePeriod();
                    asp.StartDate = Datetime.newInstanceGmt(action.effectiveStartDate, Time.newInstance(0,0,0,0));
                    asp.EndDate = Datetime.newInstanceGmt(rightStart.addDays(-1), Time.newInstance(23,59,59,0));
                    asp.oneTimeAmount = action.oneTimeAmount;

                    // System.debug('ASP: ' + JSON.serialize(asp));
                    // System.debug('AA: ' + JSON.serialize(action));
                    if(action.recurringAmount != null) {
                        asp.Mrr = PWUtils.unprorate(
                            action.getRecurringPart(
                                action.effectiveStartDate, 
                                asp.EndDate.dateGmt()
                            ),
                            action.effectiveStartDate,
                            asp.EndDate.dateGmt(),
                            PWUtils.ProrationMethod.MONTHLY_DAILY,
                            PWUtils.Period.MONTH
                        );
                    }
                    asp.Quantity = action.QuantityChange;
                    newPeriods.add(asp);
                }
                if(!rightPeriod) {
                    // there is a gap between end of right-most current period and action end; create new right period from left end -> action end
                    // System.debug('\t\tCASE 7');
                    StagedAssetStatePeriod asp = new StagedAssetStatePeriod();
                    asp.StartDate = Datetime.newInstanceGmt(leftEnd.addDays(1), Time.newInstance(0,0,0,0));
                    if(action.effectiveEndDate != null) {
                        asp.EndDate = Datetime.newInstanceGmt(action.effectiveEndDate, Time.newinstance(23,59,59,0));
                    }
                    asp.oneTimeAmount = 0;
                    if(action.recurringAmount != null && action.recurringAmount > 0) {
                        asp.Mrr = PWUtils.unprorate(
                            action.getRecurringPart(
                                asp.StartDate.dateGmt(), 
                                action.effectiveEndDate
                            ),
                            asp.StartDate.dateGmt(), 
                            action.effectiveEndDate, 
                            PWUtils.ProrationMethod.MONTHLY_DAILY, 
                            PWUtils.Period.MONTH
                        );
                    }
                    asp.Quantity = action.QuantityChange;
                    StagedAssetStatePeriod lastPd = asset.AssetStatePeriods[asset.AssetStatePeriods.size() - 1];
                    if(asp.Mrr.setScale(5) == lastPd.Mrr.setScale(5) && asp.Quantity == lastPd.Quantity && asp.oneTimeAmount == 0) {
                        // No significant difference here, so just extend existing ASP instead of creating another
                        lastPd.EndDate = asp.EndDate;
                    } else {
                        newPeriods.add(asp);
                    }
                }
            }
            asset.AssetStatePeriods.addAll(newPeriods);
        }
        for (Integer idxOfIdx = combinedidxs.size() - 1; idxOfIdx >= 0; idxOfIdx--) {
            asset.AssetActions.remove(combinedIdxs[idxofIdx]);
        }
        if(combinedAction != null) {
            combinedAction.applied = true;
            asset.AssetActions.add(combinedAction);
            // System.debug('\tCOMBINED ACTION: ' + JSON.serialize(combinedAction));
        }
        
        if(asset.AssetStatePeriods.size() > 1) {
            asset.AssetStatePeriods.sort();
            // System.debug('\tPRE-COLLAPSED ASPS:' + JSON.serialize(asset.AssetStatePeriods));
            StagedAssetStatePeriod combAsp;
            StagedAssetStatePeriod right = asset.AssetStatePeriods[0];
            List<StagedAssetStatePeriod> collapsed = new List<StagedAssetStatePeriod>();
            for (Integer idx = 1; idx < asset.AssetStatePeriods.size(); idx++ ) {
                StagedAssetStatePeriod left;
                if(combAsp != null) {
                    left = combAsp;
                } else {
                    left = asset.AssetStatePeriods[idx - 1];
                }
                right = asset.AssetStatePeriods[idx];
                if(left.Mrr == right.Mrr && left.Quantity == right.Quantity) {
                    // keep the left, kill the right
                    left.EndDate = right.EndDate;
                    if(left.oneTimeAmount == null) {
                        left.oneTimeAmount = right.oneTimeAmount;
                    } else if(right.oneTimeAmount != null) {
                        left.oneTimeAmount += right.oneTimeAmount;
                    }
                    combAsp = left;
                    right = null;
                } else {
                    if(combAsp == null) {
                        collapsed.add(left);
                    }else {
                        collapsed.add(combAsp);
                        combAsp = null;
                    }
                }
            }
            if(combAsp != null) {
                collapsed.add(combAsp);
            }
            if(right != null && (collapsed.size() == 0 || right.Quantity > 0 || right.Amount > 0)) {
                collapsed.add(right);
            }
            // System.debug('\tCOLLAPSED ASPS: ' + JSON.serialize(collapsed));
            asset.AssetStatePeriods = collapsed;
        }
        System.debug('\tFINAL ASPs: ' + JSON.serialize(asset.AssetStatePeriods));
    }

    public static void combineActions(StagedAsset asset) {
        
    }

    public static List<StagedAssetAction> mergeActions(List<StagedAssetAction> toMerge) {
        System.debug('*** MERGING ACTIONS ***');
        System.debug('\tACTIONS: ' + JSON.serialize(toMerge));
        Map<String,StagedAssetAction> merged = new Map<String,StagedAssetAction>();
        Map<String,StagedAssetAction> openActions = new Map<String,StagedAssetAction>();
        for (StagedAssetAction action : toMerge) {
            if(action.effectiveEndDate == null) {
                StagedAssetAction openAction;
                if(openActions.containsKey(action.effectiveStartDate + '')) {
                    openAction = openActions.get(action.effectiveStartDate + '');
                } else {
                    openActions.put(action.effectiveStartDate + '', action);
                    continue;
                }
                if(openAction.oneTimeAmount == null) {
                    openAction.oneTimeAmount = action.oneTimeAmount;
                } else if (action.oneTimeAmount != null) {
                    openAction.oneTimeAmount += action.oneTimeAmount;
                }
                openActions.put(action.effectiveStartDate + '', openAction);
                continue;
            }
            String key = action.effectiveStartDate + '|' + action.effectiveEndDate;
            StagedAssetAction mergedAction;
            if(merged.containsKey(key)) {
                mergedAction = merged.get(key);
            } else {
                merged.put(key, action.clone());
                continue;
            }
            if(action.recurringAmount != null) {
                if(mergedAction.recurringAmount == null) {
                    mergedAction.recurringAmount = action.recurringAmount;
                } else {
                    mergedAction.recurringAmount += action.recurringAmount;
                }
            }
            if(action.oneTimeAmount != null) {
                if(mergedAction.oneTimeAmount == null) {
                    mergedAction.oneTimeAmount = action.oneTimeAmount;
                } else {
                    mergedAction.oneTimeAmount += action.oneTimeAmount;
                }
            }
            mergedAction.AssetActionSources.addAll(action.AssetActionSources);
        }
        for (String key : merged.keySet()) {
            String startDateStr = key.split('|')[0];
            for (String openKey : openActions.keySet()) {
                if(openKey == startDateStr) {
                    StagedAssetAction openAction = openActions.get(openKey);
                    StagedAssetAction mergedAction = merged.get(key);
                    if(openAction.oneTimeAmount != null) {
                        mergedAction.oneTimeAmount += openAction.oneTimeAmount;
                    }
                }
            }
        }
        System.debug('\tMERGED ACTIONS: ' + JSON.serialize(merged));
        return merged.values();
    }

    public static void rollUpActions(NestedObject tree) {
        for (NestedObject node : tree.bottomUp()) {
            // System.debug('TREE ROOT ID: ' + tree.obj.Id);
            // System.debug('PROD ID: ' + ((StagedAsset) node.obj).Product2Id);
            List<StagedAssetAction> toMerge = new List<StagedAssetAction>();
            if(node.obj == null || ((StagedAsset) node.obj).AssetActions == null) {
                System.debug(node);
                System.debug(JSON.serialize(tree));
                System.assert(false);
            }
            // System.debug('\tINITIAL ACTIONS: ' + JSON.serialize(((StagedAsset) node.obj).AssetActions));
            for (StagedAssetAction action : ((StagedAsset) node.obj).AssetActions) {
                if(action.stagedFor == StagedRecord.StagedAction.InsertAction && action.applied == false) {
                    toMerge.add(StagedAssetAction.copy(action));
                }
            }
            String childStatus;
            Date firstGoLive;
            Boolean unifiedStatus = true;
            if(node.children != null) {
                Boolean hasChildActions = false;
                for (NestedObject child : node.children) {
                    StagedAsset childAsset = (StagedAsset) child.obj;
                    // System.debug('\tCHILD PROD ID: ' + childAsset.Product2Id);
                    // System.debug('\tMERGING ACTIONS: '  + JSON.serialize(((StagedAsset) child.obj).AssetActions));
                    for (StagedAssetAction action : ((StagedAsset) child.obj).AssetActions) {
                        if(action.stagedFor == StagedRecord.StagedAction.InsertAction && action.applied == false && action.rollUp) {
                            StagedAssetAction childAction = StagedAssetAction.copy(action);
                            childAction.QuantityChange = 0; // don't roll-up quantity changes;
                            toMerge.add(childAction);
                            hasChildActions = true;
                        }
                    }
                    if(childStatus == null) {
                        childStatus = ((StagedAsset) child.obj).Status;
                    } else if (childStatus != ((StagedAsset) child.obj).Status) {
                        unifiedStatus = false;
                    }
                    if(childAsset.Status == 'Installed' && ((Date) childAsset.get('Go_Live_Date__c')) < firstGoLive) {
                        firstGoLive = (Date) childAsset.get('Go_Live_Date__c');
                    }
                }

                // System.debug('\tHAS CHILD ACTIONS: ' + hasChildActions);

                if(unifiedStatus && ((StagedAsset) node.obj).Status != childStatus) {
                    ((StagedAsset) node.obj).Status = childStatus;
                    if(childStatus == 'Installed') {
                        ((StagedAsset) node.obj).set('Go_Live_Date__c', firstGoLive);
                    }
                } else if(!hasChildActions) {
                    continue;
                }
                if(hasChildActions) {
                    // System.debug('TO MERGE: ' + JSON.serialize(toMerge));
                    List<StagedAssetAction> mergedActions;
                    if(toMerge.size() == 1) {
                        mergedActions = new List<StagedAssetAction>{toMerge[0]};
                    } else {
                        mergedActions = mergeActions(toMerge);
                    }
                    ((StagedAsset) node.obj).AssetActions = mergedActions;
                }
                ((StagedAsset) node.obj).touch();
            }
            System.debug('\tFINAL ACTIONS: ' + JSON.serialize(((StagedAsset) node.obj).AssetActions));
            Boolean flaggedNew = (Boolean) node.getData(DataKeys.IS_NEW.name());
            if((flaggedNew != null && flaggedNew) || ((StagedAsset) node.obj).stagedFor == StagedRecord.StagedAction.InsertAction) {
                ((StagedAsset) node.obj).ParentId = node.parentId;
            }
        }
    }

    public static NestedObject aggregate(NestedObject tree, Id aggregateAccountId) {
        /**
         * 1. find existing aggregate tree
         *      if doesn't exist, create and add to cache
         * 2. merge in new/changed source nodes
         */
        System.assertNotEquals(null, tree.obj);
        System.assert(((StagedRecord) tree.obj).isInstanceOf('Asset'));

        // System.debug('AGGREGATING TREE:\n'+JSON.serialize(tree));
        // System.debug('***DATA (AGG ENTRY)***\n'+StagedDatabase.toJSON());
        Date firstGoLive;
        StagedAsset aggAsset = (StagedAsset) ((StagedAsset) tree.obj).getLookup('Aggregate_Asset__r'); // should be the root agg asset
        if(aggAsset == null) {
            // System.debug('**NO AGG ASSET AGAINST AGG CHILD');
            aggAsset = (StagedAsset) StagedDatabase.findOne(new FindAssetByProductId((Id) ((StagedAsset) tree.obj).get('Product2Id'), AssetType.Contract, tree.obj.Id));
            //aggAsset = (StagedAsset) StagedDatabase.findOne(new FindAssetByProductId((Id) ((StagedAsset) tree.obj).get('Product2Id'), AssetType.Contract, tree.obj.Id));
            if(aggAsset != null) {
                // System.debug('****EXISTING AGG ASSET FOUND, LINKING...');
                ((StagedAsset) tree.obj).setLookup('Aggregate_Asset__r', aggAsset);
            }
            // System.debug('AGG ASSET: ' + JSON.serialize(aggAsset));
        }
        NestedObject aggTree;
        if(aggAsset != null) {
            aggTree = aggAsset.getTree();
            // System.debug('EXISTING AGG TREE: ' + JSON.serialize(aggTree));
        } else {
            // I'M HERE TRYING TO GENERATE A NEW AGG AND/OR MERGE
            // StagedAsset newAggAsset = createAggregateAsset((StagedAsset) tree.obj, aggregateAccountId);
            aggTree = new NestedObject(
                createAggregateAsset((StagedAsset) tree.obj, aggregateAccountId)
            );
            aggTree.setData(DataKeys.IS_NEW.name(), true);
        }
        // System.debug('AGG TREE:\n'+JSON.serialize(aggTree));
        for (NestedObject node : tree.all()) {
            Boolean nodeChanged = (Boolean) node.getData(DataKeys.IS_CHANGED.name());
            Boolean nodeNew = (Boolean) node.getData(DataKeys.IS_NEW.name());
            if(nodeNew == null) {
                nodeNew = ((StagedAsset) node.obj).stagedFor == StagedRecord.StagedAction.InsertAction;
            }
            if(nodeChanged == null) {
                nodeChanged = ((StagedAsset) node.obj).stagedFor == StagedRecord.StagedAction.UpdateAction;
                // if (nodeChanged) {
                //     System.debug('****CHANGING NODE****');
                // }
            }
            if((nodeChanged == null || !nodeChanged) && (nodeNew == null || !nodeNew)) {
                continue;
            }
            NestedObject aggNode;
            aggAsset = (StagedAsset) ((StagedAsset) node.obj).getLookup('Aggregate_Asset__r');
            StagedAsset nodeAsset = (StagedAsset) node.obj;
            Date nodeGoLiveDate = (Date) nodeAsset.get('Go_Live_Date__c');
            if(aggAsset == null) {
                aggNode = aggTree.find(new FindAssetByProductId((Id) node.obj.get('Product2Id'), AssetType.Contract));
                if(aggNode != null) {
                    aggAsset = (StagedAsset) aggNode.obj;
                    ((StagedAsset) node.obj).setLookup('Aggregate_Asset__r', aggAsset);
                }
            }
            // System.debug('AGGREGATING: ' + JSON.serialize(node.obj));
            // System.debug('LINKED AGG ASSET: ' + JSON.serialize(aggAsset));
            if(aggAsset != null && aggNode == null) {
                aggNode = aggTree.findById(aggAsset.Id);
                if(aggNode == null) {
                    String aggParentId = (String) ((StagedAsset) tree.findById(node.parentId).obj).get('Aggregate_Asset__c');
                    NestedObject aggParentNode = aggTree.findById(aggParentId);
                    // System.debug('AGG PARENT ID: ' + aggParentId);
                    // System.debug('AGG PARENT NODE: ' + aggParentNode);
                    if(aggParentNode != null) {
                        aggNode = aggParentNode.addChild(aggAsset);
                        aggAsset.setLookup('Parent', (StagedRecord) aggParentNode.obj);
                    }
                }
                // System.debug('EXISTING AGG NODE: ' + JSON.serialize(aggNode));
            } else if (aggAsset == null) {
                // System.debug('CREATING NEW AGG ASSET');
                aggAsset = createAggregateAsset((StagedAsset) node.obj, aggregateAccountId);
                aggNode = aggTree.find(new FindAssetByProductId((Id) node.obj.get('Product2Id'), AssetType.Contract));
                // System.debug('AGG NODE: ' + JSON.serialize(aggNode)); // should be null
                if(aggNode == null) {
                    // System.debug('FINDING NEW AGG PARENT *** NODE PARENT ID: ' + node.parentId);
                    String aggParentId = (String) tree.findById(node.parentId).obj.get('Aggregate_Asset__c');
                    // System.debug('AGG PARENT ID: ' + aggParentId);
                    aggAsset.setReference('ParentId', aggParentId);
                    aggNode = aggTree.add(
                        aggAsset,
                        aggParentId
                    );
                    nodeNew = true;
                } else {
                    System.debug('AGG TREE: ' + JSON.serialize(aggTree));
                    System.assert(false, 'Aggregate asset exists but not found in node tree.');
                }
                ((StagedAsset) node.obj).setLookup('Aggregate_Asset__r', aggAsset);
                // System.debug('NEW AGG NODE: ' + JSON.serialize(aggAsset));
            }
            // Get first go live date
            if(nodeGoLiveDate < firstGoLive || firstGoLive == null) {
                firstGoLive = nodeGoLiveDate;
            }
            // System.debug('Node go live date');
            // System.debug(nodeGoLiveDate);
            aggNode.setData(DataKeys.IS_CHANGED.name(), nodeChanged);
            aggNode.setData(DataKeys.IS_NEW.name(), nodeNew);
        }
        // System.debug('First go live date');
        // System.debug(firstGoLive);
        for (NestedObject node : aggTree.bottomUp()) {
            // System.debug('AGG NODE: ' + JSON.serialize(node));
            Boolean isChanged = (Boolean) node.getData(DataKeys.IS_CHANGED.name());
            if(isChanged == null) {
                isChanged = false;
            }
            Boolean isNew = (Boolean) node.getData(DataKeys.IS_NEW.name());
            if(isNew == null) {
                isNew = false;
            }
            if((isChanged != null && isChanged) || (isNew != null && isNew)) {
                // System.debug('RE-AGGREGATING: '+JSON.serialize(node));
                List<StagedRecord> aggChildren = (List<StagedRecord>) StagedDatabase.query(new FindByAggregateAssetId(node.obj.Id));
                if(aggChildren.size() == 0) {
                    System.debug(StagedDatabase.toJSON());
                }
                System.assertNotEquals(0,aggChildren.size(), 'Aggregate should not exist without site assets.');
                String status;
                Date goLiveDate;
                List<StagedAssetAction> toAddActions = new List<StagedAssetAction>();
                for (StagedRecord rec : aggChildren) {
                    if(!tree.contains(rec.Id)) {
                        // only aggregate on the input tree. 
                        continue;
                    }
                    String recStatus = (String) rec.get('Status');
                    if(status == null) {
                        // Default to child record status
                        status = recStatus;
                    } else if (status != recStatus) {
                        // If multiple statuses, -> pending
                        status = 'Pending';
                    }
                    // System.debug('AGG CHILD ACTIONS: ' + ((StagedAsset) rec).AssetActions.size());
                    for(StagedAssetAction aa : ((StagedAsset) rec).AssetActions) {
                        if(aa.stagedFor == StagedRecord.StagedAction.InsertAction && aa.applied == false) {
                            StagedAssetAction aggChildAction = StagedAssetAction.copy(aa);
                            aggChildAction.AssetId = node.obj.Id;
                            aggChildAction.initiate();
                            if(aa.rollUp != aggChildAction.rollUp) {
                                System.debug('***MISMATCH***');
                            }
                            toAddActions.add(aggChildAction);
                        }
                    }
                }
                
                // System.debug('\tAGG.TO_ADD_ACTIONS: ' + JSON.serialize(toAddActions));
                ((StagedAsset) node.obj).AssetActions.addAll(toAddActions);
                ((StagedAsset) node.obj).Status = status;
                ((StagedAsset) node.obj).set('Go_Live_Date__c', firstGoLive);
                ((StagedAsset) node.obj).touch();
                // System.debug('AGGREGATING ID: ' + node.obj.Id);
                NestedObject parent = aggTree.findById(node.parentId);
                if(parent != null) {
                    // System.debug('Parent ID: ' + parent.obj.Id);
                    parent.setData(DataKeys.IS_CHANGED.name(),true);
                }
            }
        }
        return aggTree;
    }

    private static StagedAsset createAsset(StagedRecord oi) {
        StagedAsset a = new StagedAsset();
        a.Name = (String) oi.get('Product2.Name');
        a.CurrencyIsoCode = (String) oi.get('CurrencyIsoCode');
        // Start by twinning from QL and OI
        if(oi.get('SBQQ__QuoteLine__c') != null) {
            SBQQ__QuoteLine__c ql = (SBQQ__QuoteLine__c) PWUtils.selectStar('SBQQ__QuoteLine__c', 'Id = \'' + oi.get('SBQQ__QuoteLine__c') + '\'')[0];
            PWUtils.twinFields(new StagedRecord(ql), a, new String[]{'Name'});
            a.set('Original_Quote_Line__c', (Id) oi.get('SBQQ__QuoteLine__c'));
        }
        // System.debug('TWINNING FROM ORDER ITEM: ' + JSON.serialize(oi));
        PWUtils.twinFields(oi, a, new String[]{'Name'});
        // System.debug('TWINNED ASSET: ' + JSON.serialize(a));
        a.AccountId = (Id) oi.get('SBQQ__ShippingAccount__c');
        a.Status = 'Purchased';

        // StagedAssetStatePeriod asp = createPeriod(oi);
        StagedAssetAction aa = createAction(oi);
        aa.AssetActionSources.add(createSource(oi));
        
        a.AssetActions.add(aa);
        // a.AssetStatePeriods.add(asp);

        a.initiate();

        oi.setLookup('Asset__r', a);

        StagedDatabase.put(a);
        // System.debug('STAGED: ' + StagedDatabase.get(a.Id).toJSON());

        return a;
    }

    private static StagedAsset createAggregateAsset(StagedAsset a, Id aggregateAccountId) {
        // System.debug('PRE-COPY: ' + JSON.serialize(a));
        StagedAsset aggAsset = StagedAsset.copy(a);

        aggAsset.setReference('ParentId', null);
        // Clear ASPs so they are re-generated based on actions.
        aggAsset.AssetStatePeriods = new List<StagedAssetStatePeriod>();
        aggAsset.AssetActions = new List<StagedAssetAction>();
        aggAsset.set('AccountId', aggregateAccountId);
        aggAsset.Id = null;
        aggAsset.initiate(); // reinitiate w/ new accountId


        // System.debug('COPIED:' + JSON.serialize(aggAsset));
        a.setLookup('Aggregate_Asset__r', aggAsset);
        // System.debug('LINKED: ' + JSON.serialize(a));
        StagedDatabase.put(aggAsset);
        // System.debug('UPDATED BASE ASSET:\n' + a.toJSON());
        // System.debug(StagedDatabase.toJSON());
        // System.debug('SHOULD MATCH:\n'+ StagedDatabase.get(a.Id).toJSON());
        return aggAsset;
    }

    private static Double getMrr (StagedRecord oi) {
        Decimal amount = (Decimal) oi.get('TotalPrice');
        Double mrr = 0.0;
        if((String) oi.get('SBQQ__ChargeType__c') == 'Recurring') {
            return PWUtils.unprorate(amount, getStartDate(oi), getEndDate(oi), PWUtils.ProrationMethod.MONTHLY_DAILY, PWUtils.Period.MONTH);
        }
        return mrr;
    }
    private static StagedAssetAction createAction(StagedRecord oi) {
        Double lineTotal = (Double) oi.get('TotalPrice');
        String lineAction = (String) oi.get('SBQQ__ContractAction__c');
        Double qtyChange = (Double) oi.get('Quantity');
        StagedAssetAction.Category action;
        if(oi.get('Asset__c') != null){
            if(lineAction == 'Price Change' || lineAction == 'Site Change') {
                action = StagedAssetAction.Category.Other;
                qtyChange = 0.0;
            } else if(lineTotal > 0) {
                action = StagedAssetAction.Category.Upsells;
            } else if(lineTotal < 0) {
                action = StagedAssetAction.Category.Downsells;
            } else {
                action = StagedAssetAction.Category.Other;
            }
        } else {
            action = StagedAssetAction.Category.Initial_Sale;
        }
        StagedAssetAction aa = new StagedAssetAction(new AssetAction(
            ActionDate = Datetime.now(),
            QuantityChange = qtyChange,
            MrrChange = getMrr(oi),
            Amount = lineTotal
        ));
        aa.CategoryEnum = action;
        if(oi.get('SBQQ__ChargeType__c') == 'One-Time') {
            aa.oneTimeAmount = lineTotal;
        } else if (oi.get('SBQQ__ChargeType__c') == 'Recurring') {
            aa.recurringAmount = lineTotal;
        }
        aa.effectiveEndDate = getEndDate(oi);
        aa.effectiveStartDate = getStartDate(oi);
        return aa;
    }

    private static Date getStartDate(StagedRecord oi) {
        Date startDate = (Date) oi.get('Start_Date__c');
        if(startDate == null) {
            startDate = (Date) oi.get('ServiceDate');
        }
        return startDate;
    }
    private static Date getEndDate(StagedRecord oi) {
        if(oi.get('SBQQ__ChargeType__c') == 'One-Time') {
            return null;
        }
        Date endDate = (Date) oi.get('End_Date__c');
        if(endDate == null) {
            endDate = (Date) oi.get('EndDate');
        }
        return endDate;
    }

    private static AssetActionSource createSource(StagedRecord oi) {

        Date endDate = getEndDate(oi);
        
        AssetActionSource aas = new AssetActionSource(
            TransactionDate = (Datetime) oi.get('Order.EffectiveDate'),
            StartDate = Datetime.newInstanceGmt(getStartDate(oi), Time.newInstance(0,0,0,0)),
            EndDate = endDate == null ? null : Datetime.newInstanceGmt(getEndDate(oi), Time.newInstance(23, 59, 59, 0)),
            Quantity = (Double) oi.get('Quantity'),
            ProductAmount = (Double) oi.get('TotalPrice'),
            ReferenceEntityItemId = oi.Id
        );
        return aas;
    }

    private static StagedAsset updateAssetFromOrderItem(StagedAsset asset, StagedRecord orderItem) {
        // need to handle special cancellation case (e.g. qty 4 now, 6 in 2 months but want to cancel all)
        // System.debug('UPDATING ASSET: ' + asset.Id);
        System.assert(PWUtils.isId(asset.Id), 'Existing asset has invalid id.');
        // TODO
        Date startDate = (Date) orderItem.get('ServiceDate');
        Date endDate = (Date) orderItem.get('EndDate');
        StagedRecord quoteLine = StagedDatabase.get((String) orderItem.get('SBQQ__QuoteLine__c'));
        StagedRecord aggRoot = StagedDatabase.get((String) asset.get('Aggregate_Asset__r.RootAssetId'));
        PWUtils.twinFields(quoteLine, asset, new String[]{'Name'});
        PWUtils.twinFields(orderItem, asset, new String[]{'Name'});
        Double oiContractRev = (Double) orderItem.get('Contract_Revision__c');
        if(aggRoot != null && aggRoot.get('Revision__c') != oiContractRev) {
            aggRoot.set('Revision__c', oiContractRev);
        }
        List<StagedAssetStatePeriod> asps = asset.AssetStatePeriods;
        String contractAction = (String) orderItem.get('SBQQ__ContractAction__c');
        Double existingMrr = 0.0;
       
        // System.debug('Contract Action: ' + contractAction);
        // LTC-2754
        if(contractAction == 'Site Change') {
            asset.AccountId = (Id) orderItem.get('SBQQ__ShippingAccount__c');
        }

        if(contractAction == 'Re-contract') {
            Date actionDate = (Date) orderItem.get('ServiceDate');
            StagedAssetStatePeriod asp;
            Double remainingAspTotal = 0.0;
            Double remainingAspOTTotal = 0.0;
            for(StagedAssetStatePeriod currAsp : asset.AssetStatePeriods) {
                if(currAsp.StartDate.dateGmt() <= actionDate && currAsp.EndDate.dateGmt() >= actionDate) {
                    asp = currAsp;
                } else if (currAsp.StartDate.dateGmt() > actionDate) {
                    remainingAspTotal += currAsp.Amount;
                    remainingAspOTTotal += currAsp.oneTimeAmount;
                }
            }
            StagedAssetAction endAction = new StagedAssetAction(new AssetAction(
                ActionDate = Datetime.now()
            ));
            endAction.effectiveStartDate = (Date) orderItem.get('ServiceDate');
            endAction.effectiveEndDate  = ((Datetime) asset.get('LifecycleEndDate')).dateGMT();
            endAction.oneTimeAmount = -1.0 * (remainingAspOTTotal + remainingAspTotal);
            endAction.MrrChange = -1.0 * asp.Mrr;
            endAction.QuantityChange = -1.0 * asp.Quantity;
            endAction.CategoryEnum = StagedAssetAction.Category.Other;
            asset.AssetActions.add(endAction);
        }
        StagedAssetAction aa = createAction(orderItem);
        aa.AssetActionSources.add(createSource(orderItem));
        asset.AssetActions.add(aa);

        asset.initiate();
        asset.touch();

        return asset;
    }

    // BUSINESS LOGIC - INTERFACE IMPLENTATIONS

    private class AssignOrderItemToAsset implements NestedObject.AssignFunction {
        public NestedObject.AssignResult assign(NestedObject.Nestable targetObj, NestedObject.Nestable sourceObj, Map<String, Object> data) {
            StagedAsset a;
            data.remove(DataKeys.IS_NEW.name());
            data.remove(DataKeys.IS_CHANGED.name());
            if(targetObj == null) {
                // net new
                a = createAsset((StagedRecord) sourceObj);
                StagedDatabase.put(a);
                data.put(DataKeys.IS_NEW.name(), true);
            } else {
                // System.debug('***ASSIGNING***\nTARGET:\n' + ((StagedRecord) targetObj).toJSON() + '\nSOURCE:\n'+((StagedRecord) sourceObj).toJSON());
                a = updateAssetFromOrderItem(
                    (StagedAsset) targetObj,
                    (StagedRecord) sourceObj
                );
                data.put(DataKeys.IS_CHANGED.name(), true);
            }
            return new NestedObject.AssignResult(a, data);
        }
    }

    private class FindTreeForId implements StagedDatabase.QueryFunction {
        private String assetId;
        public FindTreeForId(String id) {
            assetId = id;
        }
        public Boolean match(StagedRecord rec) {
            return rec.getType() == 'Asset' && (rec.Id == this.assetId || ((StagedAsset) rec).RootAssetId == this.assetId) && ((StagedAsset) rec).Status != 'Cancelled';
        }
    }

    private class FindByAggregateAssetId implements StagedDatabase.QueryFunction {
        private String aggAssetId;
        public FindByAggregateAssetId (String aggAssetId) {
            this.aggAssetId = aggAssetId;
        }
        public Boolean match(StagedRecord rec) {
            return rec.isInstanceOf('Asset') && (String) rec.get('Aggregate_Asset__c') == this.aggAssetId;
        }
    }

    private class RetrieveStagedRecords implements AssetManagementProcessTask.PreProcessingHook {
        private Set<String> recordIds;
        public RetrieveStagedRecords(Set<String> recordIds) {
            this.recordIds = recordIds;
        }
        public void process(AssetManagementProcessTask task) {
            task.records = StagedRecord.getRecords(StagedDatabase.get(this.recordIds));
        }
    }

    public class AfterAssetInsertHook implements AssetManagementProcessTask.PostProcessingHook {
        public String recordId;
        public StagedAsset isolatedRecord;
        // public List<SubsequentAssetChange> subsequentChanges;
        public AfterAssetInsertHook (String recordId) {
            this.recordId = recordId;
        }
        public AfterAssetInsertHook (StagedAsset record) {
            this.recordId = record.Id;
            this.isolatedRecord = record;
        }
        public void process(AssetManagementProcessTask task, AssetManagementProcessTask.Result result) {
            Tranquility.AssetServiceResponse resp = new Tranquility.AssetServiceResponse(result.response);
            // System.debug('INSERTED: ' + this.recordId + ' -> ' + resp.asset.Id);
            StagedAsset a = (StagedAsset) StagedDatabase.get(this.recordId);
            if(a == null) {
                a = this.isolatedRecord;
            }
            a.Id = resp.asset.Id;
            for (AssetStatePeriod respPd : resp.assetStatePeriods) {
                for (StagedAssetStatePeriod pd : a.AssetStatePeriods) {
                    if(pd.stagedFor == StagedRecord.StagedAction.InsertAction) {
                        pd.AssetId = a.Id;
                        pd.Id = respPd.Id;
                    }
                }
            }
            StagedAssetAction taskAa;
            for (StagedAssetAction aa : a.AssetActions) {
                if(aa.stagedFor != StagedRecord.StagedAction.NoAction) {
                    taskAa = aa;
                    taskAa.AssetId = a.Id;
                    taskAa.Id = resp.assetAction.Id;
                    break;
                }
            }
            if(taskAa != null && taskAa.AssetActionSources != null) {
                for (Integer idx = 0; idx < taskAa.AssetActionSources.size() && idx < resp.assetActionSources.size(); idx++) {
                    taskAa.AssetActionSources[idx].Id = resp.assetActionSources[idx].Id;
                }
            }
        }
    }

    private class FindAssetByProductId implements NestedObject.FilterFunction, StagedDatabase.QueryFunction{
        private Id prodId;
        private AssetType type;
        private String excludeId;
        public FindAssetByProductId(Id prodId, AssetType type) {
            this.prodId = prodId;
            this.type = type;
        }
        public FindAssetByProductId(Id prodId, AssetType type, String excludeId) {
            this.prodId = prodId;
            this.type = type;
            this.excludeId = excludeId;
        }
        private Boolean internalTest(StagedRecord rec) {
            if(this.type == null) {
                return rec.getType() == 'Asset' && (Id) rec.get('Product2Id') == this.prodId;
            } else {
                switch on this.type {
                    when Contract {
                        return rec.getType() == 'Asset' && (Id) ((StagedAsset) rec).get('Product2Id') == this.prodId && ((StagedAsset) rec).get('Aggregate_Asset__c') == null && (this.excludeId != null ? rec.Id != this.excludeId : true);
                    } when Site {
                        return rec.getType() == 'Asset' && (Id) ((StagedAsset) rec).get('Product2Id') == this.prodId && ((StagedAsset) rec).get('Aggregate_Asset__c') != null && (this.excludeId != null ? rec.Id != this.excludeId : true);
                    } when else {
                        return null;
                    }
                }
            }
        }
        public Boolean test(NestedObject.Nestable obj, Map<String,Object> data) {
            return this.internalTest((StagedRecord) obj);
        }
        public Boolean match(StagedRecord rec) {
            return this.internalTest(rec);
        }
    }

    public interface SerenityFinalizer {
        void execute ();
        void execute (StagedDatabase.State dbState);
    }

    public class BlockConfig {
        Integer threshold;
        Integer taskSize;
        public BlockConfig(Integer threshold, Integer taskSize){
            this.threshold = threshold;
            this.taskSize = taskSize;
        }
    }

    public class BatchConfig {
        public Integer blocksPerBatch = 1;
        public List<BlockConfig> blockConfigs;
        public List<String> namedCredentials;
        public BatchConfig(){
            // Default configurations
            this.addBlockConfig(new BlockConfig(8,8)); // complexity < 8 ~2 ASPs
            this.addBlockConfig(new BlockConfig(14,3)); // complexity < 14 ~4 ASPs
            this.addBlockConfig(new BlockConfig(null,1));
        }
        public void addBlockConfig(BlockConfig config){
            // add to configs, keeping thresholds in sequence
            if(this.blockConfigs == null){
                // not yet initialised. initialise and add -> done
                this.blockConfigs = new List<BlockConfig>();
                this.blockConfigs.add(config);
                return;
            }
            if(config.threshold == null) {
                // no threshold always goes at the end -> done
                this.blockConfigs.add(config);
                return;
            }
            if(config.threshold > this.blockConfigs[this.blockConfigs.size() - 1].threshold) {
                // new config is already in order. add to end -> done
                this.blockConfigs.add(config);
                return;
            }
            // new config goes somewhere within existing configs. Sort it out.
            List<BlockConfig> newConfigs = new List<BlockConfig>();
            Boolean added = false;
            for (BlockConfig cfg : this.blockConfigs) {
                if(config.threshold < cfg.threshold){
                    added = true;
                    newConfigs.add(config);
                }
                newConfigs.add(cfg);
            }
            if(!added){
                newConfigs.add(config);
            }
            this.blockConfigs = newConfigs;
        }
        public BatchConfig(Integer blocksPerBatch, List<BlockConfig> blockConfigs) {
            this.blocksPerBatch = blocksPerBatch;
            this.blockConfigs = blockConfigs;
        }
    }
    public class PreSubsequentChangeTask implements AssetManagementProcessTask.PreProcessingHook {
        String baseId;
        Tranquility.UpsertAssetRequest req;
        public PreSubsequentChangeTask(String baseId, Tranquility.UpsertAssetRequest req) {
            this.baseId = baseId;
            this.req = req;
        }
        public void process(AssetManagementProcessTask task) {
            String newId = StagedDatabase.get(baseId).Id;
            if(newId == null) {
                System.debug('NULL SUBS CHANGE ID');
                System.debug(this.baseId);
                System.debug(StagedDatabase.toJSON());
                System.assert(false,'Aborted');
            }
            if(!PWUtils.isId(newId)) {
                AssetManagementLog.logError(new SerenityException('Subsequent change processed with invalid id.'), null, 'Subsequent Change');
                return;
            }
            if(newId != this.baseId) {
                // Id has changed. Update task request
                task.request = (new Tranquility.ChangeAssetRequest(this.req,newId)).prepareRequest();
            }
        }
    }

    public class SerenityException extends Exception{}
}