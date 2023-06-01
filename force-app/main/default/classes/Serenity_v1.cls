public without sharing class Serenity_v1 {
    

    // public static BatchConfig config = new BatchConfig();

    // ENUMs
    private enum DataKeys {
        IS_NEW,
        IS_CHANGED
    }
    /*
    public enum AsyncAction {
        Order,
        OrderUpdate,
        CancelOne,
        CancelTree,
        CancelAll,
        EndDate
    }

    // PROPERTIES
    //      static members
    private static String sourceAction;
    private static Id internalDeletedAssetAccountId;
    private static Id sourceId;
    private static Serenity.SerenityFinalizer batchFinalizer;
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
        //TODO: add fields
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
        //TODO: add fields
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
    public static Id AsyncRequest(AsyncAction action, Id inputId) {
        return AsyncRequest(action, inputId, null);
    }
    public static Id AsyncRequest(AsyncAction action, Id inputId, Date inputDate) {
        if(Test.isRunningTest()) {
            switch on action {
                when Order {
                    return Order(inputId);
                }
                when OrderUpdate {
                    return OrderUpdate(inputId);
                }
                when CancelAll {
                    return CancelAll(inputId);
                }
                when CancelOne {
                    return CancelOne(inputId);
                }
                when CancelTree {
                    return CancelTree(inputId);
                }
                when EndDate {
                    EndDate(inputId, inputDate);
                    return process();
                }
            }
        }
        return System.enqueueJob(new AsyncHandler(action, inputId, inputDate));
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
            // System.debug('INITIAL DATA:\n' + dbJson);
            Map<String,NestedObject> roots = new Map<String,NestedObject>();
            Map<String,String>  rootTypes = new Map<String,String>();
            Set<Id> toAggregateRoots = new Set<Id>();
            Set<Id> recontractRoots = new Set<Id>();
            Map<Id,Date> recontractDates = new Map<Id,Date>();
            // Loop over order items and store roots -- either bundle id (oi tree to be created as new assets) or root asset id
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
                // System.debug('ROOT ID:' + rootId);
                NestedObject root;
                if(roots.keySet().contains(rootId)) {
                    // rootId already staged in the map--retrieve it
                    root = roots.get(rootId);
                } else {
                    // rootId not yet staged in map--add it
                    if(type == 'BUNDLE') {
                        if(oi.Id == rootId) {
                            NestedObject newRoot = new NestedObject(oi);
                            root = roots.put(rootId, newRoot);
                            lineIsRoot = true;
                            if(oi.get('SBQQ__ContractAction__c') == 'Re-contract'){
                                Id contractRootId = (Id) oi.get('Asset__r.Aggregate_Asset__r.RootAssetId');
                                recontractRoots.add(contractRootId);
                                recontractDates.put(contractRootId, (Date) oi.get('ServiceDate'));
                            }
                        } else if(!roots.containsKey(rootId)) {
                            NestedObject newRoot = new NestedObject(new StagedRecord(new OrderItem(Id=rootId)));
                            roots.put(rootId, newRoot);
                        }
                    } else {
                        System.assertEquals('ASSET', type); // should be the case
                        if((Id) oi.get('Asset__c') == rootId) {
                            // Root asset is actually present on the order
                            root = roots.put(rootId, new NestedObject(oi));
                            lineIsRoot = true;
                        } else {
                            // Root asset not present on the order (normal for an amendment)
                            root = new NestedObject(new StagedAsset());
                            roots.put(rootId, root);
                            // System.debug('INSERTED ROOT:'+root);
                        }
                    }
                    // Store the root type
                    rootTypes.put(rootId, type);
                    if(oi.get('Order.AccountId') != oi.get('SBQQ__ShippingAccount__c')) {
                        toAggregateRoots.add(rootId);
                    }
                }
                if(!lineIsRoot) {
                    NestedObject newNode = root.add(oi, (Id) oi.get(parentField));
                }
            }
            for (String rootId : roots.keySet()) {
                NestedObject root = roots.get(rootId);
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
                    }
                    when 'BUNDLE' {
                        StagedAsset parent;
                        String parentId = null;
                        for (NestedObject node : root.all()) {
                            StagedAsset a;
                            // Handling for MDQ lines
                            if(((StagedRecord) node.obj).get('SBQQ__SegmentIndex__c') != null) {
                                NestedObject existingNode = root.find(new FindAssetByProductId((Id)((StagedRecord) node.obj).get('Product2Id')));
                                if(existingNode != null) {
                                    a = (StagedAsset) existingNode.obj;
                                    a.AssetStatePeriods.add(createPeriod((StagedRecord) node.obj));
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
                
                rollUpValues(root);
                // System.debug('POST ROLL:\n'+JSON.serialize(root));
                if(toAggregateRoots.contains(rootId)) {
                    // LTC-2564 - only aggregate when site is different than customer
                    aggregate(root, o.AccountId);
                }
            }
            for (Id contractRootId : recontractRoots) {
                for (StagedRecord record : StagedDatabase.all()) {
                    if(record.getType() == 'Asset' && record.stagedFor == StagedRecord.StagedAction.NoAction) {
                        if(record.get('Aggregate_Asset__r.RootAssetId') == contractRootId) {
                            EndDate(record.Id, recontractDates.get(contractRootId));
                        }
                    }
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
                if(oi.get('SBQQ__Status__c') == 'Completed') {
                    OrderItemUpdate(oi);
                    String rootId = getRootAssetId(oi);
                    if(!rootIds.contains(rootId)) {
                        rootIds.add(rootId);
                    }
                }
            }
            for (String rootId : rootIds) {
                NestedObject tree = getAssetTree(rootId);
                // System.debug('TREE PRE-ROLL: ' + JSON.serialize(tree));
                rollUpValues(tree);
                aggregate(tree, o.AccountId);
            }
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
        a.Status = 'Cancelled';
        Decimal amount;
        Decimal mrr;
        Decimal quantity;
        for (StagedAssetStatePeriod asp : a.AssetStatePeriods) {
            if(asp.StartDate <= asOf && asp.EndDate > asOf) {
                amount = asp.Amount;
                asp.EndDate = asOf;
                amount -= asp.Amount;
                mrr = asp.Mrr;
                quantity = asp.Quantity;
            } else if(asp.StartDate > asOf) {
                amount += asp.Amount;
            }
        }
        StagedAssetAction aa = new StagedAssetAction();
        aa.ActionDate = Datetime.now();
        aa.Amount = -1.0 * amount;
        aa.MrrChange = -1.0 * mrr;
        aa.QuantityChange = -1.0 * quantity;
        aa.CategoryEnum = StagedAssetAction.Category.Cancellations;
        a.AssetActions.add(aa);
    }

    public static Id CancelOne(Id assetId) {
        sourceId = assetId;
        sourceAction = 'Cancel Asset';
        StagedDatabase.addWhere('Asset', 'Id = \'' + assetId + '\'',assetExpandFields, StagedAsset.class);
        StagedAsset a = (StagedAsset) StagedDatabase.get(assetId);
        a.AccountId = deletedAssetAccountId;
        a.Status = 'Cancelled';
        return process();
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

        // List<AssetManagementProcessTask> largeTasks = new List<AssetManagementProcessTask>();
        // List<AssetManagementProcessTask> medTasks = new List<AssetManagementProcessTask>();
        // List<AssetManagementProcessTask> smallTasks = new List<AssetManagementProcessTask>();
        // List<AssetManagementProcessTask> finalTasks = new List<AssetManagementProcessTask>();
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
    public static Id process(Serenity.SerenityFinalizer finalizer) {
        batchFinalizer = finalizer;
        return process();
    }
    public static Id process() {
        return process(false);
    }
    private static Id process(Boolean isAsync) {
        queue = new List<AssetManagementProcessTask>();
        // String finalData = StagedDatabase.toJSON();
        // System.debug('PROCESSED DATA:\n' + finalData);
        List<String> assetsToUpdate = new List<String>();
        List<String> orderItemsToUpdate = new List<String>();
        for(StagedRecord record : StagedDatabase.all()){
            switch on record.getType() {
                when 'Asset' {
                    switch on record.stagedFor {
                        when UpdateAction {
                            queueAssetUpdate((StagedAsset) record);
                            assetsToUpdate.add(record.Id);
                        }
                        when InsertAction {
                            queueAssetInsert((StagedAsset) record);
                            assetsToUpdate.add(record.Id);
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
            }
        }
        if(assetsToUpdate.size() > 0) {
            AssetManagementProcessTask updateAssetTask = new AssetManagementProcessTask(
                AssetManagementProcessTask.Operation.DML_UPDATE,
                new SObject[]{}
            );
            updateAssetTask.before(new RetrieveStagedRecords(assetsToUpdate));
            queue.add(updateAssetTask);
        }
        if(orderItemsToUpdate.size() > 0) {
            AssetManagementProcessTask updateOrderItemTask = new AssetManagementProcessTask(
                AssetManagementProcessTask.Operation.DML_UPDATE,
                new SObject[]{}
            );
            updateOrderItemTask.before(new RetrieveStagedRecords(orderItemsToUpdate));
            queue.add(updateOrderItemTask);
        }   
        // System.debug('***FINAL TASK QUEUE***\n' + JSON.serialize(queue));
        // if(USE_BATCH) {
        //     queue = AssetManagementProcessTask.batchify(queue);
        // }
        if(isAsync) {
            return null;
        }
        if(Test.isRunningTest()) {
            for (AssetTaskBlock block : buildBlocks(queue)) {
                System.debug('TASK BLOCK: ' + JSON.serialize(block));
                block.process();
            }
            if(batchFinalizer != null) {
                batchFinalizer.execute();
            }
            return null;
        } else {
            return Database.executeBatch(new BatchableProcessAssetManagementTasks(queue, StagedDatabase.getState(), sourceId, sourceAction, batchFinalizer), config.blocksPerBatch);
        }
    }

    private static void queueAssetUpdate(StagedAsset record) {
        // Compare existing record to staged record and generate Tranquility request
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
                        return; // already cancelled
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
            for (StagedAssetStatePeriod period : record.AssetStatePeriods) {
                if(period.stagedFor != StagedRecord.StagedAction.NoAction) {
                    asp = new Tranquility.AssetStatePeriodInput(period);
                    break;
                }
            }
            if(asp == null) {
                asp = new Tranquility.AssetStatePeriodInput();
                asp.startDate = record.LifecycleStartDate;
                asp.endDate = record.LifecycleEndDate;
                asp.mrr = (Double) record.get('CurrentMrr');
                asp.quantity = (Double) record.get('CurrentQuantity');
                asp.amount = (Double) record.get('CurrentAmount');
                req.assetStatePeriod = asp;
            }
            queue.add(req.generateTask());
        } else {
            Tranquility.ChangeAssetRequest req = new Tranquility.ChangeAssetRequest(record);
            queue.add(req.generateTask());
        }
    }

    private static void queueAssetInsert(StagedAsset record) {
        Tranquility.GenerateAssetRequest req = new Tranquility.GenerateAssetRequest(record);
        List<SubsequentAssetChange> changeReqs;
        Tranquility.UpsertAssetRequest baseReq = req;
        while (baseReq.aspOverflow != null) {
            if(changeReqs == null) {
                changeReqs = new List<SubsequentAssetChange>();
            }
            Tranquility.ChangeAssetRequest changeReq = new Tranquility.ChangeAssetRequest(baseReq);
            changeReqs.add(new SubsequentAssetChange(changeReq));
            baseReq = changeReq;
        }
        AssetManagementProcessTask task = req.generateTask();
        task.after(new AfterAssetInsertHook(record.Id, changeReqs));
        queue.add(task);
        if(changeReqs != null) {
            queue.addAll(subsequentTaskList(changeReqs));
        }
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

    private static NestedObject getAssetTree(Id rootId) {
        NestedObject tree = new NestedObject(
            StagedDatabase.query(new FindTreeForId(rootId)),
            'Id',
            'ParentId'
        );
        // System.debug('***TREE***:\n'+JSON.serialize(tree));
        for (NestedObject node : tree.all()) {
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
        StagedAsset asset = (StagedAsset) StagedDatabase.get((Id) orderItem.get('Asset__c'));
        Date initialStart = (Date) orderItem.get('ServiceDate'); // 2024-01-30
        Date finalStart = (Date) orderItem.get('Start_Date__c'); // 2024-03-
        Date finalEnd = (Date) orderItem.get('End_Date__c');
        if(finalEnd == null) {
            finalEnd = (Date) orderItem.get('SBQQ__BundleRoot__r.EndDate');
        }
        if(initialStart != finalStart) {
            for(Integer i = 0; i < asset.AssetStatePeriods.size(); i++) {
                StagedAssetStatePeriod asp = asset.AssetStatePeriods[i];
                if(asp.StartDate.dateGmt() == initialStart) {
                    if(i > 0) {
                        // Extend previous period and adjust start of this period
                        asset.AssetStatePeriods[i - 1].EndDate = Datetime.newInstanceGmt(finalStart, Time.newInstance(23,59,59,0));
                        if(asset.AssetStatePeriods.size() >= i + 2) {
                            asset.AssetstatePeriods[i + 1].StartDate = Datetime.newInstanceGmt(finalEnd, Time.newInstance(0,0,0,0)).addDays(1);
                        }
                        asp.StartDate = Datetime.newInstanceGmt(finalStart, Time.newInstance(0,0,0,0));
                        asp.EndDate = Datetime.newInstanceGmt(finalEnd, Time.newInstance(23,59,59,0));
                    } else {
                        // add new filler period to beginning
                        StagedAssetStatePeriod filler = new StagedAssetStatePeriod();
                        filler.Quantity = 0;
                        filler.Mrr = 0;
                        filler.oneTimeAmount = 0;
                        // filler.Amount = 0;
                        filler.StartDate = asp.StartDate;
                        filler.EndDate = Datetime.newInstanceGmt(finalStart, Time.newInstance(0,0,0,0)).addSeconds(-1);
                        asset.AssetStatePeriods.add(0,filler);
                        // Update this period with finalised dates
                        asp.StartDate = Datetime.newInstanceGmt(finalStart, Time.newInstance(0,0,0,0));
                        asp.EndDate = Datetime.newInstanceGmt(finalEnd, Time.newInstance(23,59,59,0));
                    }
                }
            }
        }
        StagedAssetAction aa = new StagedAssetAction();
        aa.ActionDate = Datetime.now();
        aa.MrrChange = 0.0;
        aa.Amount = 0.0;
        aa.QuantityChange = 0.0;
        aa.CategoryEnum = StagedAssetAction.Category.Other;
        aa.AssetActionSources.add(createSource(orderItem));
        asset.AssetActions.add(aa);
        if(orderItem.get('SBQQ__Status__c') == 'Completed') {
            asset.Status = 'Installed';
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

    private static Id getRootAssetId(StagedRecord oi) {
        if(oi.get('Asset__c') != null){
            return (Id) oi.get('Asset__r.RootAssetId');
        }
        Id rootAssetId = (Id) oi.get('SBQQ__QuoteLine__r.BundleRoot__r.Asset__c');
        return rootAssetId;
    }
    */
    public static void rollUpValues(NestedObject tree) {
        // System.debug('ROLLING UP:'+JSON.serialize(tree));
        for(NestedObject node : tree.bottomUp()) {
            Boolean needsUpdate = false;
            Boolean isNew = (Boolean) node.getData(DataKeys.IS_NEW.name());
            if(isNew == null) {
                isNew = ((StagedAsset) node.obj).stagedFor == StagedRecord.StagedAction.InsertAction;
                // isNew = false;
            }
            List<StagedAssetStatePeriod> periods = new List<StagedAssetStatePeriod>();
            for (StagedAssetStatePeriod currentPeriod : ((StagedAsset) node.obj).AssetStatePeriods) {
                periods.add(currentPeriod);
            }
            StagedAssetAction action;
            List<Id> sourceIds = new List<Id>();
            List<Id> existingSourceIds = new List<Id>();
            for (StagedAssetAction aa : ((StagedAsset) node.obj).AssetActions) {
                if(aa.stagedFor == StagedRecord.StagedAction.InsertAction) {
                    action = aa;
                    for (AssetActionSource aas : aa.AssetActionSources) {
                        sourceIds.add(aas.ReferenceEntityItemId);
                        existingSourceIds.add(aas.ReferenceEntityItemId);
                    }
                }
            }
            if(node.children != null) {
                for (NestedObject child : node.children) {
                    // System.debug('TO-ROLL CHILD:'+JSON.serialize(child));
                    if(child.getData(DataKeys.IS_NEW.name()) == true || child.getData(DataKeys.IS_CHANGED.name()) == true || ((StagedAsset) child.obj).stagedFor == StagedRecord.StagedAction.InsertAction) {
                        needsUpdate = true;
                    }
                    for (StagedAssetStatePeriod sasp : ((StagedAsset) child.obj).AssetStatePeriods) {
                        periods.add(sasp);
                    }
                    for (StagedAssetAction aa : ((StagedAsset) child.obj).AssetActions) {
                        if(aa.stagedFor == StagedRecord.StagedAction.InsertAction) {
                            Boolean isActionSource = false;
                            if(action == null) {
                                isActionSource = true;
                                action = StagedAssetAction.copy(aa);
                                ((StagedAsset) node.obj).AssetActions.add(action);
                                ((StagedAsset) node.Obj).initiate();
                            } else {
                                action.Amount += aa.Amount;
                                action.MrrChange = aa.MrrChange;
                            }
                            for(AssetActionSource aas : aa.AssetActionSources) {
                                if(!sourceIds.contains(aas.ReferenceEntityItemId)) {
                                    sourceIds.add(aas.ReferenceEntityItemId);
                                    if(isActionSource) {
                                        existingSourceIds.add(aas.ReferenceEntityItemId);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if(needsUpdate) {
                // System.debug('ROll-UP > UPDATING:\n'+((StagedAsset) node.obj).toJSON());
                if(node.getData(DataKeys.IS_NEW.name()) != true) {
                    node.setData(DataKeys.IS_CHANGED.name(), true);
                }
                List<StagedAssetStatePeriod> existingPeriods = ((StagedAsset) node.obj).AssetStatePeriods;
                List<StagedAssetStatePeriod> finalPeriods = new List<StagedAssetStatePeriod>();
                // System.debug(JSON.serialize(existingPeriods));
                // System.debug(JSON.serialize(periods));
                // System.debug(JSON.serialize(TimePeriod.normalize(periods, new String[]{'quantity'}, StagedAssetStatePeriod.class)));
                for(Periodic pd : TimePeriod.normalize(periods, new String[]{'quantity'}, StagedAssetStatePeriod.class)) {
                    Boolean match = false;
                    for(StagedAssetSTatePeriod existingPd : existingPeriods) {
                        if(pd.equals(existingPd)) {
                            // System.debug('ROLL-UP > MAINTAINING EXISTING PERIOD');
                            match = true;
                            finalPeriods.add(existingPd);
                            break;
                        }
                    }
                    if(!match){
                        // System.debug('ROLL-UP > ADDING NEW PERIOD');
                        // System.debug(JSON.serialize(pd));
                        finalPeriods.add((StagedAssetStatePeriod) pd);
                    }
                }
                for(Id sourceId : sourceIds) {
                    if(!existingSourceIds.contains(sourceId)) {
                        action.AssetActionSources.add(createSource(StagedDatabase.get(sourceId)));
                        if(action.AssetActionSources.size() == 10) {
                            break;
                        }
                    }
                }
                ((StagedAsset) node.obj).AssetStatePeriods = finalPeriods;
                ((StagedAsset) node.Obj).touch();
            }
            if(isNew){
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

        // System.debug('AGGREGATING:\n'+JSON.serialize(tree));
        // System.debug('***DATA (AGG ENTRY)***\n'+StagedDatabase.toJSON());
        
        StagedAsset aggAsset = (StagedAsset) ((StagedAsset) tree.obj).getLookup('Aggregate_Asset__r'); // should be the root agg asset
        NestedObject aggTree;
        if(aggAsset != null) {
            aggTree = aggAsset.getTree();
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
            if((nodeChanged == null || !nodeChanged) && (nodeNew == null || !nodeNew)) {
                continue;
            }
            aggAsset = (StagedAsset) ((StagedAsset) node.obj).getLookup('Aggregate_Asset__r');
            NestedObject aggNode;
            if(aggAsset != null) {
                aggNode = aggTree.findById(aggAsset.Id);
                // System.debug('EXISTING AGG NODE' + JSON.serialize(aggNode));
            } else {
                // System.debug('CREATING NEW AGG ASSET');
                aggAsset = createAggregateAsset((StagedAsset) node.obj, aggregateAccountId);
                aggNode = aggTree.find(new FindAssetByProductId((Id) node.obj.get('Product2Id')));
                if(aggNode == null) {
                    String aggParentId = (String) tree.findById(node.parentId).obj.get('Aggregate_Asset__c');
                    aggAsset.setReference('ParentId', aggParentId);
                    aggNode = aggTree.add(
                        aggAsset,
                        aggParentId
                    );
                    aggNode.setData(DataKeys.IS_NEW.name(),true);
                } else {
                    System.assert(false, 'Aggregate asset exists but not found in node tree.');
                }
                ((StagedAsset) node.obj).setLookup('Aggregate_Asset__r', aggAsset);
            }
            aggNode.setData(DataKeys.IS_CHANGED.name(), nodeChanged);
            aggNode.setData(DataKeys.IS_NEW.name(), nodeNew);
        }
        for (NestedObject node : aggTree.bottomUp()) {
            Boolean isChanged = (Boolean) node.getData(DataKeys.IS_CHANGED.name());
            if(isChanged == null) {
                isChanged = false;
            }
            Boolean isNew = (Boolean) node.getData(DataKeys.IS_NEW.name());
            if(isNew == null) {
                isNew = false;
            }
            if((isChanged != null && isChanged) || (isNew != null && isNew)) {
                // System.debug('RE-AGGREGATING:\n'+JSON.serialize(node));
                List<StagedRecord> aggChildren = (List<StagedRecord>) StagedDatabase.query(new FindByAggregateAssetId(node.obj.Id));
                if(aggChildren.size() == 0){
                    // System.debug('***DATA***\n' + StagedDatabase.toJSON());
                }
                System.assertNotEquals(0,aggChildren.size(), 'Aggregate should not exist without site assets.');
                List<Periodic> periods = new List<Periodic>();
                StagedAssetAction action = new StagedAssetAction();
                action.MrrChange = 0.0;
                action.Amount = 0.0;
                action.QuantityChange = 0.0;
                String status;
                for (StagedRecord rec : aggChildren) {
                    String recStatus = (String) rec.get('Status');
                    if(status == null) {
                        // Default to child record status
                        status = recStatus;
                    } else if (status != recStatus) {
                        // If multiple statuses, -> pending
                        status = 'Pending';
                    }
                    for (StagedAssetStatePeriod pd : ((StagedAsset) rec).AssetStatePeriods) {
                        periods.add(StagedAssetStatePeriod.copy(pd));
                    }
                    for(StagedAssetAction aa : ((StagedAsset) rec).AssetActions) {
                        if(aa.stagedFor == StagedRecord.StagedAction.InsertAction) {
                            action.MrrChange += aa.MrrChange;
                            action.Amount += aa.Amount;
                            action.ActionDate = aa.ActionDate; // assuming this doesn't vary across lines
                            action.QuantityChange += aa.QuantityChange;
                            for( AssetActionSource aas : aa.AssetActionSources) {
                                for (AssetActionSource existing : action.AssetActionSources) {
                                    if(aas.ReferenceEntityItemId != existing.ReferenceEntityItemId && action.AssetActionSources.size() < 10) {
                                        action.AssetActionSources.add(aas.clone());
                                    }
                                }
                            }
                        }
                    }
                }
                List<StagedAssetStatePeriod> finalPeriods = new List<StagedAssetStatePeriod>();
                List<StagedAssetStatePeriod> normalized = new List<StagedAssetStatePeriod>();
                for(Periodic period : TimePeriod.normalize(periods, null, null, StagedAssetStatePeriod.class)) {
                    Boolean matched = false;
                    for(StagedAssetStatePeriod existingPeriod : ((StagedAsset) node.obj).AssetStatePeriods) {
                        if(period.equals(existingPeriod)) {
                            matched = true;
                            finalPeriods.add(existingPeriod);
                            break;
                        }
                    }
                    if(!matched) {
                        finalPeriods.add((StagedAssetStatePeriod) period);
                    }
                }
                if(isNew){
                    action.CategoryEnum = StagedAssetAction.Category.Initial_Sale;
                } else if(action.Amount > 0) {
                    action.CategoryEnum = StagedAssetAction.Category.Upsells;
                } else if(action.Amount < 0) {
                    action.CategoryEnum = StagedAssetAction.Category.Downsells;
                } else {
                    action.CategoryEnum = StagedAssetAction.Category.Other;
                }

                ((StagedAsset) node.obj).Status = status;
                ((StagedAsset) node.obj).AssetStatePeriods = finalPeriods;
                ((StagedAsset) node.obj).AssetActions.add(action);
                ((StagedAsset) node.obj).touch();

                NestedObject parent = aggTree.findById(node.parentId);
                if(parent != null) {
                    parent.setData(DataKeys.IS_CHANGED.name(),true);
                }
            }
        }
        return aggTree;
    }
    /*

    private static StagedAsset createAsset(StagedRecord oi) {
        StagedAsset a = new StagedAsset();
        a.Name = (String) oi.get('Product2.Name');
        a.CurrencyIsoCode = (String) oi.get('CurrencyIsoCode');
        // Start by twinning from QL and OI
        if(oi.get('SBQQ__QuoteLine__c') != null) {
            SBQQ__QuoteLine__c ql = (SBQQ__QuoteLine__c) PWUtils.selectStar('SBQQ__QuoteLine__c', 'Id = \'' + oi.get('SBQQ__QuoteLine__c') + '\'')[0];
            PWUtils.twinFields(new StagedRecord(ql), a, new String[]{'Name'});
        }
        PWUtils.twinFields(oi, a, new String[]{'Name'});
        a.AccountId = (Id) oi.get('SBQQ__ShippingAccount__c');
        a.Status = 'Purchased';

        StagedAssetStatePeriod asp = createPeriod(oi);
        StagedAssetAction aa = createAction(oi);
        aa.AssetActionSources.add(createSource(oi));
        
        a.AssetActions.add(aa);
        a.AssetStatePeriods.add(asp);

        a.initiate();

        oi.setLookup('Asset__r', a);

        StagedDatabase.put(a);

        return a;
    }

    */

    private static StagedAsset createAggregateAsset(StagedAsset a, Id aggregateAccountId) {
        // System.debug('PRE-COPY:\n'+StagedDatabase.get(a.Id).toJSON());
        StagedAsset aggAsset = StagedAsset.copy(a);
        aggAsset.AssetStatePeriods = new List<StagedAssetStatePeriod>();
        aggAsset.AssetActions = new List<StagedAssetAction>();
        aggAsset.set('AccountId', aggregateAccountId);
        aggAsset.Id = null;
        aggAsset.initiate(); // reinitiate w/ new accountId

        a.setLookup('Aggregate_Asset__r', aggAsset);
        StagedDatabase.put(aggAsset);
        // System.debug('UPDATED BASE ASSET:\n' + a.toJSON());
        // System.debug('SHOULD MATCH:\n'+ StagedDatabase.get(a.Id).toJSON());
        return aggAsset;
    }

    /*

    private static Double getMrr (StagedRecord oi) {
        Decimal amount = (Decimal) oi.get('TotalPrice');
        Double mrr = 0.0;
        if((String) oi.get('SBQQ__ChargeType__c') == 'Recurring') {
            
            // Double term = (Double) oi.get('SBQQ__SubscriptionTerm__c');
            // if(term == null) {
            //     term = (Double) oi.get('SBQQ__BundleRoot__r.SBQQ__SubscriptionTerm__c'); // TODO: won't work for add-ons
            // }
            // if(term != null) {
            //     return amount / term;
            // }
            Date startDate = (Date) oi.get('Start_Date__c');
            if(startDate == null) {
                startDate = (Date) oi.get('ServiceDate');
            }
            Date endDate = (Date) oi.get('End_Date__c');
            if(endDate == null) {
                endDate = (Date) oi.get('EndDate');
            }
            return PWUtils.unprorate(amount, startDate, endDate, PWUtils.ProrationMethod.MONTHLY_DAILY, PWUtils.Period.MONTH);
        }
        return mrr;
    }

    private static StagedAssetStatePeriod createPeriod(StagedRecord oi) {
        Date endDate = (Date) oi.get('End_Date__c');
        if(endDate == null) {
            endDate = (Date) oi.get('EndDate');
        }
        Date startDate = (Date) oi.get('Start_Date__c');
        if(startDate == null) {
            startDate = (Date) oi.get('ServiceDate');
        }
        if(endDate == null) {
            endDate = (Date) oi.get('SBQQ__BundleRoot__r.End_Date__c');
            if(endDate == null) {
                endDate = (Date) oi.get('SBQQ__BundleRoot__r.EndDate');
            }
            if(endDate == null) {
                throw new SerenityException('No end date for root item');
            }
        }
        StagedAssetStatePeriod asp = new StagedAssetStatePeriod();
        System.debug('QUANTITY: ' + oi.get('Quantity'));
        asp.Quantity = (Double) oi.get('Quantity');
        asp.StartDate = Datetime.newInstanceGmt(startDate, Time.newInstance(0,0,0,0));
        asp.EndDate = Datetime.newInstanceGmt(endDate,Time.newInstance(23,59,59,0));
        asp.Mrr = getMrr(oi);
        if(oi.get('SBQQ__ChargeType__c') == 'One-Time') {
            asp.oneTimeAmount = (Decimal) oi.get('TotalPrice');
        }
        return asp;
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
        return aa;
    }
    */

    private static AssetActionSource createSource(StagedRecord oi) {
        Date startDate = (Date) oi.get('Start_Date__c');
        if(startDate == null) {
            startDate = (Date) oi.get('ServiceDate');
        }
        Date endDate = (Date) oi.get('End_Date__c');
        if(endDate == null) {
            endDate = (Date) oi.get('EndDate');
        }
        AssetActionSource aas = new AssetActionSource(
            TransactionDate = (Datetime) oi.get('Order.EffectiveDate'),
            StartDate = Datetime.newInstanceGmt(startDate, Time.newInstance(0,0,0,0)),
            EndDate = Datetime.newInstanceGmt(endDate, Time.newInstance(23, 59, 59, 0)),
            Quantity = (Double) oi.get('Quantity'),
            ProductAmount = (Double) oi.get('TotalPrice'),
            ReferenceEntityItemId = oi.Id
        );
        return aas;
    }
    /*

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
        if(aggRoot.get('Revision__c') != oiContractRev) {
            aggRoot.set('Revision__c', oiContractRev);
        }
        List<StagedAssetStatePeriod> asps = asset.AssetStatePeriods;
        String contractAction = (String) orderItem.get('SBQQ__ContractAction__c');
        Double existingMrr = 0.0;
        if(contractAction == 'Re-contract' || contractAction == 'Site Change' || contractAction == 'Price Change') {
            Integer[] removeIdxs = new Integer[]{};
            Integer idx = 0;
            for (StagedAssetStatePeriod asp : asps) {
                if(asp.StartDate <= startDate && asp.EndDate > startDate) {
                    // Overlapping existing ASP
                    asp.EndDate = Datetime.newInstanceGmt(startDate.addDays(-1), Time.newInstance(23,59,59,0));
                    existingMrr = asp.Mrr;
                } else if(asp.StartDate > startDate) {
                    // Starts after the new period ends.
                    removeIdxs.add(idx);
                }
                idx++;
            }
            // TODO: Need more detailed handling here for the different change types.
            for (Integer jdx : removeIdxs) {
                asps.remove(jdx);
            }
        }
        // System.debug('Contract Action: ' + contractAction);
        // LTC-2754
        if(contractAction == 'Site Change') {
            asset.AccountId = (Id) orderItem.get('SBQQ__ShippingAccount__c');
        }
        StagedAssetStatePeriod newAsp = createPeriod(orderItem);
        if(contractAction == 'Price Change') {
            // System.debug('EXISTING MRR: ' + existingMrr);
            // System.debug('NEW MRR: ' + newAsp.Mrr);
            newAsp.Mrr += existingMrr;
        }
        asps.add(newAsp);
        List<StagedAssetStatePeriod> normalizedPeriods = new List<StagedAssetStatePeriod>();
        for(Periodic pd : TimePeriod.normalize(asps, null, null, StagedAssetStatePeriod.class)) {
            normalizedPeriods.add((StagedAssetStatePeriod) pd);
        }
        // System.debug('NORMALIZED PERIODS:\n'+JSON.serialize(normalizedPeriods));
        asset.AssetStatePeriods = normalizedPeriods;
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
            return rec.getType() == 'Asset' && (rec.Id == this.assetId || rec.get('RootAssetId') == this.assetId);
        }
    }

    */

    private class FindByAggregateAssetId implements StagedDatabase.QueryFunction {
        private String aggAssetId;
        public FindByAggregateAssetId (String aggAssetId) {
            this.aggAssetId = aggAssetId;
        }
        public Boolean match(StagedRecord rec) {
            return rec.isInstanceOf('Asset') && (String) rec.get('Aggregate_Asset__c') == this.aggAssetId;
        }
    }

    /*

    private class AsyncHandler implements Queueable, Database.AllowsCallouts {
        AsyncAction action;
        Id inputId;
        Date inputDate;
        String namedCredential;
        public AsyncHandler(AsyncAction action, Id inputId, Date inputDate) {
            this.action = action;
            this.inputId = inputId;
            this.inputDate = inputDate;
            this.namedCredential = Serenity_v1.namedCredential;
        }
        public void execute(QueueableContext ctx) {
            Serenity_v1.namedCredential = this.namedCredential;
            Id jobId;
            switch on this.action {
                when Order {
                    jobId = Order(this.inputId);
                }
                when OrderUpdate {
                    jobId = OrderUpdate(this.inputId);
                }
                when CancelTree {
                    jobId = CancelTree(this.inputId);
                }
                when CancelOne {
                    jobId = CancelOne(this.inputId);
                }
                when CancelAll {
                    jobId = CancelAll(this.inputId);
                }
                when EndDate {
                    EndDate(this.inputId, this.inputDate);
                    jobId = process();
                }
            }
            // Swap the job id so CPQ can track the asset updates on the page
            try {
                SBQQ__RecordJob__c recJob = [SELECT Id FROM SBQQ__RecordJob__c WHERE SBQQ__JobId__c = :ctx.getJobId().to15()];
                if(recJob != null) {
                    recJob.SBQQ__JobId__c = jobId;
                    update recJob;
                }
            } catch (QueryException e){
                // do nothing
            }
        }
    }

    private class RetrieveStagedRecords implements AssetManagementProcessTask.PreProcessingHook {
        private List<String> recordIds;
        public RetrieveStagedRecords(List<String> recordIds) {
            this.recordIds = recordIds;
        }
        public void process(AssetManagementProcessTask task) {
            task.records = StagedRecord.getRecords(StagedDatabase.get(this.recordIds));
        }
    }

    public class AfterAssetInsertHook implements AssetManagementProcessTask.PostProcessingHook {
        public String recordId;
        public StagedAsset isolatedRecord;
        public List<SubsequentAssetChange> subsequentChanges;
        public AfterAssetInsertHook (String recordId) {
            this.recordId = recordId;
        }
        public AfterAssetInsertHook (String recordId, List<SubsequentAssetChange> subsequentChanges) {
            this.recordId = recordId;
            this.subsequentChanges = subsequentChanges;
        }
        public AfterAssetInsertHook (StagedAsset record) {
            this.recordId = record.Id;
            this.isolatedRecord = record;
        }
        public AfterAssetInsertHook (StagedAsset record, List<SubsequentAssetChange> subsequentChanges) {
            this.recordId = record.Id;
            this.isolatedRecord = record;
            this.subsequentChanges = subsequentChanges;
        }
        public void process(AssetManagementProcessTask task, AssetManagementProcessTask.Result result) {
            Tranquility.AssetServiceResponse resp = new Tranquility.AssetServiceResponse(result.response);
            StagedAsset a = (StagedAsset) StagedDatabase.get(this.recordId);
            if(a == null) {
                a = this.isolatedRecord;
            }
            a.Id = resp.asset.Id;
            Integer pdIdx = 0;
            for (StagedAssetStatePeriod pd : a.AssetStatePeriods) {
                if(pd.stagedFor == StagedRecord.StagedAction.InsertAction) {
                    pd.Id = resp.assetStatePeriods[pdIdx].Id;
                    pdIdx++;
                }
            }
            StagedAssetAction taskAa;
            for (StagedAssetAction aa : a.AssetActions) {
                if(aa.stagedFor != StagedRecord.StagedAction.NoAction) {
                    taskAa = aa;
                    taskAa.Id = resp.assetAction.Id;
                    break;
                }
            }
            for (Integer idx = 0; idx < taskAa.AssetActionSources.size(); idx++) {
                taskAa.AssetActionSources[idx].Id = resp.assetActionSources[idx].Id;
            }
            for (StagedAssetStatePeriod asp : a.AssetStatePeriods) {
                if(asp.stagedFor != StagedRecord.StagedAction.NoAction) {
                    // Need to insert rest of the ASPs
                    AssetManagementProcessTask updateTask = (new Tranquility.ChangeAssetRequest(a)).generateTask();
                    updateTask.after(new AfterAssetInsertHook(a));
                    System.enqueueJob(new QueueableAssetManagementProcessTask(updateTask));
                }
            }
            if(this.subsequentChanges != null) {
                for (SubsequentAssetChange change : this.subsequentChanges) {
                    change.request.assetId = resp.asset.Id;
                    change.task.request = change.request.prepareRequest('change', resp.asset.Id);
                }
            }
        }
    }
    */

    private class FindAssetByProductId implements NestedObject.FilterFunction {
        private Id prodId;
        public FindAssetByProductId(Id prodId) {
            this.prodId = prodId;
        }
        public Boolean test(NestedObject.Nestable obj, Map<String,Object> data) {
            return ((StagedRecord) obj).getType() == 'Asset' && (Id) ((StagedAsset) obj).get('Product2Id') == this.prodId;
        }
    }

    /*
    //public interface SerenityFinalizer {
    //    void execute ();
    //    void execute (StagedDatabase.State dbState);
    //}
    

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

    public class SubsequentAssetChange {
        private Tranquility.ChangeAssetRequest internalRequest;
        public AssetManagementProcessTask task;
        public Tranquility.ChangeAssetRequest request {
            get{
                return this.internalRequest;
            }
            set {
                this.internalRequest = value;
                this.task = value.generateTask();
            }
        }
        public SubsequentAssetChange(Tranquility.ChangeAssetRequest req) {
            this.request = req;
        }
    }

    public static List<AssetManagementProcessTask> subsequentTaskList (List<SubsequentAssetChange> changes) {
        List<AssetManagementProcessTask> tasks = new List<AssetManagementProcessTask>();
        for (SubsequentAssetChange change : changes) {
            tasks.add(change.task);
        }
        return tasks;
    }

    public class SerenityException extends Exception{}

    */
}