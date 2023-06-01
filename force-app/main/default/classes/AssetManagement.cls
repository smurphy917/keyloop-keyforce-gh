global without sharing class AssetManagement {

    public enum PROCESS_MODE {
        SEND, 
        TASK
    }

    private static PROCESS_MODE mode = PROCESS_MODE.TASK;
    static final String LOGIK_CONFIG_ID_FIELD = 'Logik_ID_Twin__c';
    
    // Calculation class-functions
    static NestedObject.RollUpFunction newRollUp = new RollUpBeforeInsert();
    static NestedObject.RollUpFunction amendmentRollUp = new RollUpAfterDescendantChanges();
    // static NestedObject.RollUpFunction recalculateRollUp = new RollUpAsset();
    // static NestedObject.FilterFunction changedFilter = new ChangedFilterFunction();
    static NestedObject.FilterFunction createdFilter = new CreatedFilterFunction();
    static NestedObject.FilterFunction isOrderItem = new IsOrderItemFilterFunction();
    static NestedObject.FilterFunction onlyMappedLines = new ConfigurationBOMController.FilterOnlyMappedLines();

    // static AssetManagementProcessTask.PreProcessingHook preInsertAsset = new PreInsertAsset();
    static AssetManagementProcessTask.PreProcessingHook preUpdateAssets = new PreUpdateAssets();
    // static AssetManagementProcessTask.PreProcessingHook preUpdateOrderItems = new PreUpdateOrderItems();
    static AssetManagementProcessTask.PostProcessingHook postInsertAsset = new PostInsertAsset();
    // static AssetManagementProcessTask.PostProcessingHook postUpdateAssets = new PostUpdateAssets();
    static AssetManagementProcessTask.PostProcessingHook postCancelAsset = new PostCancelAsset();
    // static AssetManagementProcessTask.PreProcessingHook preAggregateAssets = new PreAggregateAssets();
    static AssetManagementProcessTask.PreProcessingHook preUpdateAggregateAssets = new PreUpdateAggregateAssets();
    static FindMatchingAsset findMatchingAsset = new FindMatchingAsset();

    private static BatchableProcessAssetManagementTasks batchProcess = new BatchableProcessAssetManagementTasks();

    private static List<AssetManagementProcessTask> queue = new List<AssetManagementProcessTask>();

    public static List<AssetManagementProcessTask> getQueue() {
        return queue;
    }

    private static List<Asset> allTouchedAssets = new List<Asset>();

    private static Map<Id, OrderItem> oi_idToSObj;

    static String staticNamedCredential;

    private static Id StandardPricebookId;

    public static List<Asset> getTouchedAssets() {
        return allTouchedAssets;
    }

    public static void setMode(PROCESS_MODE newMode){
        mode = newMode;
    }

    global static List<String> getOrderItemFields () {
        List<String> oiFields = new List<String>(new String[]{
            'CurrencyIsoCode',
            'ServiceDate',
            'Quantity',
            // 'AdjustedLineAmount',
            'SBQQ__SubscriptionTerm__c',
            'EndDate',
            'SBQQ__ChargeType__c',
            'SBQQ__BundleRoot__c',
            'Product2Id',
            'Product2.AssetConversion__c',
            'Modified_Root_Asset__c',
            'Modified_Root_Asset__r.RootAssetId',
            'SBQQ__Asset__c',
            'SBQQ__ShippingAccount__c',
            'SBQQ__QuoteLine__r.SBQQ__ComponentTotal__c',
            'SBQQ__RequiredBy__c',
            'SBQQ__BundleRoot__c',
            'SBQQ__BundleRoot__r.SBQQ__ShippingAccount__c',
            'SBQQ__QuoteLine__r.SBQQ__RequiredBy__r.SBQQ__ComponentTotal__c',
            'SBQQ__QuoteLine__r.SBQQ__RequiredBy__r.SBQQ__Product__c',
            'SBQQ__QuoteLine__r.SBQQ__RequiredBy__r.SBQQ__UpgradedAsset__c',
            'SBQQ__TaxAmount__c',
            'Order.EndDate',
            'Order.AccountId',
            'TotalPrice',
            'Product2.Name'
        });
        // if(PWUtils.hasField('OrderItem', 'MRR__c')) {
        //     oiFields.add('MRR__c');
        // }
        // if(PWUtils.hasField('OrderItem', 'Line_MRR__c')) {
        //     oiFields.add('Line_MRR__c');
        // }
        if(OrgSettings.BillingEnabled) {
            // oiFields.add('blng__BilledTax__c');
            // oiFields.add('blng__Asset__c');
        } else {
            oiFields.add('Asset__c');
        }
        
        // if(OrgSettings.LogikEnabled) {
        //     oiFields.add(LOGIK_CONFIG_ID_FIELD);
        // }
        
        return oiFields;
    }

    global static List<String> getAssetFields() {
        List<String> assetFields = new List<String>(new String[]{
            'Name',
            'Id',
            'RootAssetId',
            'Product2Id',
            'ParentId',
            'Aggregate_Asset__c',
            'AccountId',
            'CurrencyIsoCode',
            '(SELECT Id, Quantity, StartDate, EndDate FROM AssetStatePeriods)',
            'HasLifecycleManagement',
            'Quantity',
            'CurrentQuantity',
            'CurrentMrr',
            'CurrentAmount',
            'LifecycleStartDate',
            'LifecycleEndDate',
            '(SELECT ActionDate, Category FROM AssetActions ORDER BY ActionDate DESC)'
        });

        return assetFields;
    }

    global static Double getMrr(OrderItem oi) {
        if(oi.SBQQ__ChargeType__c == 'Recurring') {
            return oi.TotalPrice / oi.SBQQ__SubscriptionTerm__c;
        }
        return 0.0;
    }

    global static Double getAmount(OrderItem oi) {
        return oi.TotalPrice;
    }

    global static List<Asset> GenerateAssetsFromOrder (Id orderId, String namedCredential) {
        return GenerateAssetsFromOrder(new Order(Id=orderId), true, namedCredential);
    }

    // global static List<Asset> GenerateAssetsFromOrder (Order o, String namedCredential) {
    //     return GenerateAssetsFromOrder(o, true, namedCredential);
    // }

    global static void BatchProcess() {
        BatchProcess(1);
    }

    global static void BatchProcess(Integer recordsPerBatch) {
        if(queue.size() > 0 && !Test.isRunningTest()) {
            System.debug('Starting batch processing...');
            System.debug(JSON.serialize(queue));
            batchProcess.addTasks(queue);
            Database.executeBatch(batchProcess, recordsPerBatch);
        }
    }

    global static List<Asset> GenerateAssetsFromOrder (Order o, Boolean salesOnly, String namedCredential) {

        List<String> oiFields = getOrderItemFields();
        oi_idToSObj = new Map<Id,OrderItem>();

        staticNamedCredential = namedCredential;
        o = [SELECT Id, AccountId, EndDate, EffectiveDate FROM Order WHERE Id = :o.Id];
        List<Asset> allAssets = new List<Asset>();
        List<OrderItem> updatedOis = new List<OrderItem>();
        List<Asset> newAssets = new List<Asset>();
        // List<Asset> updatedAssets = new List<Asset>();
        List<NestedObject> toRollUp = new List<NestedObject>();
        
        AssignOrderItemToAsset assignOiToAsset = new AssignOrderItemToAsset();
        List<NestedObject> orderBoms = ConfigurationBOMController.getBOMsForOrder(o, oiFields, ConfigurationBOMController.BOM_TYPE_ORDER_LINES_ONLY);
        List<Id> rootAssetIds = new List<Id>();
        Map<Id,Datetime> startDateByRootAssetId = new Map<Id,Datetime>();
        Map<Id,NestedObject> amendmentBoms = new Map<Id,NestedObject>();
        List<Tranquility.GenerateResult> results = new List<Tranquility.GenerateResult>();
        AssetItemsFilter assetItemsFilter = new AssetItemsFilter();

        // Loop over root BOMs (could be multiple in a single order)
        for (NestedObject rootBom : orderBoms) {
            NestedObject oiNode = rootBom;
            if(!(rootBom.obj instanceof OrderItem)) {
                // Top-level sales item is not an OrderItem--this is likely because this is an amendment order, which won't include the root bundle item.
                oiNode = rootBom.find(isOrderItem); // find the first node (top-down search) that is an order item
            }
            OrderItem oi = (OrderItem) oiNode.obj;
            if(oi.Modified_Root_Asset__c != null && oi.Product2.AssetConversion__c != null){
                if(!rootAssetIds.contains(oi.Modified_Root_Asset__c)) {
                    rootAssetIds.add(oi.Modified_Root_Asset__c);
                    startDateByRootAssetId.put(oi.Modified_Root_Asset__c, oi.ServiceDate);
                    NestedObject amendmentBom;
                    if(oi.Asset__c == oi.Modified_Root_Asset__c) {
                        amendmentBom = rootBom;
                    } else {
                        amendmentBom = new NestedObject(oi.Modified_Root_Asset__r);
                        amendmentBom.addChild(rootBom);
                    }
                    amendmentBoms.put(oi.Modified_Root_Asset__c, amendmentBom);
                } else {
                    amendmentBoms.get(oi.Modified_Root_Asset__c).addChild(rootBom);
                }
            } else {
                // This is a net-new asset collection
                rootBom.rollUp(newRollUp);
                for (Object filteredNode : PWUtils.filter(rootBom.all(), assetItemsFilter)) {
                    NestedObject node = (NestedObject) filteredNode;
                    Double mrr = (Double) node.getData('mrr');
                    Double amount = (Double) node.getData('amount');
                    Tranquility.GenerateResult result = GenerateFromOrderItem((OrderItem) node.obj, namedCredential, mrr, amount);
                    results.add(result);
                    if(mode == PROCESS_MODE.SEND) {
                        node.setData('created', true);
                        node.setData('OrderItem.Id', node.obj.getId());
                        oi_idToSObj.put(node.obj.getId(), (OrderItem) node.obj);
                        node.replaceObject(result.asset);
                    } else if (mode == PROCESS_MODE.TASK) {
                        // handle similar logic in pre/post hooks
                        // updatedAssets.add(result.asset);
                    }
                }
                // Loop over new (just created) assets to set additional asset and oi fields
                for (NestedObject node : rootBom.some(createdFilter)) {
                    // newly-created asset
                    Asset newAsset = (Asset) node.obj;
                    newAsset.ParentId = node.parentId;
                    newAssets.add(newAsset);
                    OrderItem mappedOi = oi_idToSObj.get((String) node.getData('OrderItem.Id'));
                    if(OrgSettings.BillingEnabled) {
                        // PWUtils.setField(mappedOi, 'blng__Asset__c', newAsset.Id);
                        //oi.blng__Asset__c = newAsset.Id;
                    } else {
                        PWUtils.setField(mappedOi, 'Asset__c', newAsset.Id);
                    }
                    updatedOis.add(mappedOi);
                }
            }
        }
        for (Id rootAssetId : rootAssetIds) {
            NestedObject existingBom = ConfigurationBOMController.getBOMForAsset(rootAssetId, startDateByRootAssetId.get(rootAssetId), getAssetFields(), true);
            NestedObject resultBom = NestedObject.assign(
                existingBom, // target
                amendmentBoms.get(rootAssetId), // source
                'Id', // target merge ID
                'Asset__c', // source merge ID
                'SBQQ__QuoteLine__r.SBQQ__RequiredBy__r.SBQQ__UpgradedAsset__c', // Parent merge ID
                onlyMappedLines, // scope function to filter lines that are merged (filters to NOs with obj that are either QLs or OIs (or null(?)))
                assignOiToAsset // function to run against each merged item. This will call GenerateFromOrderItem for each merged or new asset
            );
            toRollUp.add(resultBom);
        }
        // allAssets.addAll(assignOiToAsset.getAssets());
        allAssets.addAll(assignOiToAsset.getAssets());
        results.addAll(assignOiToAsset.getResults());

        for (NestedObject rootBom : toRollUp) {
            // Re-calculate totals for existing assets after an amendment (have to wait until the new/updated assets are committed)
            rootBom.rollUp(amendmentRollUp);
            Map<Id,Id> oiIdToParentAssetId = (Map<Id,Id>) batchProcess.getData('OrderItemIdToParentAssetId');
            if(oiIdToParentAssetId == null) {
                oiIdToParentAssetId = new Map<Id,Id>();
            }
            for(NestedObject node : rootBom.all()) {
                Boolean created = (Boolean) node.getData('created');
                if(created != null && created) {
                    oiIdToParentAssetId.put((Id) node.getData('OrderItem.Id'), ((Asset) node.obj).ParentId);
                }
            }
            batchProcess.setData('OrderItemIdToParentAssetId', oiIdToParentAssetId);
        }
    
        
        if(mode == PROCESS_MODE.SEND && newAssets.size() > 0) {
            allAssets.addAll(newAssets);
            if(!Test.isRunningTest()) {
                update newAssets; // set parents
            }
            allAssets.addAll(AggregateAll(results));
        } else if (mode == PROCESS_MODE.TASK) {
            List<Asset> aggAssets = AggregateAll(results);  
            // Task to update (for new assets):
            //  * link to parent on asset
            //  * asset link on order item
            AssetManagementProcessTask task = new AssetManagementProcessTask(AssetManagementProcessTask.Operation.DML_UPDATE, new List<SObject>());
            task.before(preUpdateAssets);
            queue.add(task);
            // Aggregate all touched assets
            allAssets.addAll(aggAssets);
        }
        
        if(mode == PROCESS_MODE.SEND && !Test.isRunningTest()) {
            update updatedOis;
        } else if (mode == PROCESS_MODE.TASK) {
            // Handled in the preUpdateAssets hook
        }
        
        allTouchedAssets.addAll(allAssets);
        return allAssets;
    }

    // global static Tranquility.GenerateResult GenerateFromOrderItem (OrderItem oi) {
    //     return GenerateFromOrderItem (oi, null);
    // }
    
    // global static Tranquility.GenerateResult GenerateFromOrderItem (OrderItem oi, String namedCredential) {
    //     Double mrr = 0.0;
    //     if(oi.SBQQ__ChargeType__c == 'Recurring') {
    //         mrr = oi.TotalPrice / oi.SBQQ__SubscriptionTerm__c;
    //     }
    //     return GenerateFromOrderItem(oi, namedCredential, mrr, (Double) oi.TotalPrice);
    // }

    
    global static Tranquility.GenerateResult GenerateFromOrderItem (OrderItem oi, String namedCredential, Double mrr, Double amount) {
        /**
         * 1) Retrieve order item data, including parent and root (required by)
         * 2) Call the /asset-manager/assets/actions/generate service
         * 3) Update the asset w/ ParentId and RootId
         * 4) Update order item w/ asset linkage (???)
         */
        Tranquility.UpsertAssetRequest req;
        Double baseQty = 0;
        Double baseMrr = 0;
        Double baseAmt = 0;
        Boolean isNewAsset = false;

        if(namedCredential != null) {
            staticNamedCredential = namedCredential;
        }

        if(oi == null) {
            System.debug('OrderItem is null');
            throw new IllegalArgumentException('Null OrderItem');
        }
        Id oiAssetId;
        if(OrgSettings.BillingEnabled) {
            // oiAssetId = (Id) PWUtils.getField(oi, 'blng__Asset__c');
        } else {
            oiAssetId = (Id) PWUtils.getField(oi, 'Asset__c');
        }
        if(oiAssetId == null) {
            isNewAsset = true;
            Id oiAcctId = oi.SBQQ__ShippingAccount__c;
            if(oiAcctId == null && oi.SBQQ__BundleRoot__c != null) {
                oiAcctId = oi.SBQQ__BundleRoot__r.SBQQ__ShippingAccount__c;
            }
            req = new Tranquility.GenerateAssetRequest(staticNamedCredential);
            ((Tranquility.GenerateAssetRequest) req).accountId = oiAcctId;
            ((Tranquility.GenerateAssetRequest) req).assetName = oi.Product2.Name;
            ((Tranquility.GenerateAssetRequest) req).productId = oi.Product2Id;
            ((Tranquility.GenerateAssetRequest) req).currencyIsoCode = oi.CurrencyIsoCode;
        } else {
            req = new Tranquility.ChangeAssetRequest(oiAssetId, staticNamedCredential);
            Tranquility.AssetStatePeriodInput current = ((Tranquility.ChangeAssetRequest) req).getStateForTime(Datetime.newInstanceGmt(oi.ServiceDate, Time.newInstance(0,0,0,0)).addSeconds(-1));
            if(current == null) {
                throw new AssetManagementException('No period found for date: ' + oi.ServiceDate);
            }
            baseQty = current.quantity;
            baseMrr = current.mrr;
            baseAmt = current.amount;
        }
        Tranquility.AssetActionInput aa = new Tranquility.AssetActionInput();
        Tranquility.AssetStatePeriodInput asp = new Tranquility.AssetStatePeriodInput();
        Tranquility.ReferencedAssetActionSourceInput aas = new Tranquility.ReferencedAssetActionSourceInput();

        // ASP mapping
        asp.startDate = oi.ServiceDate;
        if(oi.EndDate != null) {
            asp.endDate = Datetime.newInstanceGmt(oi.EndDate,Time.newInstance(0,0,0,0)).addSeconds(-1);
        } else if (oi.Order.EndDate != null) {
            asp.endDate = Datetime.newInstanceGmt(oi.Order.EndDate,Time.newInstance(0,0,0,0)).addSeconds(-1);
        } else {
            // Default to 1 year period
            asp.endDate = Datetime.newInstanceGmt(oi.ServiceDate, Time.newInstance(0,0,0,0)).addYears(1).addSeconds(-1);
        }
        
        asp.quantity = baseQty + oi.Quantity;
        asp.mrr = baseMrr + mrr;
        asp.amount = baseAmt + amount;
        // AA mapping
        aa.category = 'Initial Sale';
        if(oiAssetId != null) {
            if(asp.quantity == 0){
                aa.category = 'Cancellations';
            } else if (oi.Quantity > 0) {
                aa.category = 'Upsells';
            } else {
                aa.category = 'Downsells';
            }
        } 
        aa.actionDate = oi.ServiceDate;
        aa.quantityChange = oi.Quantity;
        aa.mrrChange = mrr;
        aa.amount = amount;
        // AAS mapping
        aas.quantity = oi.Quantity;
        aas.productAmount = amount;
        aas.referenceEntityItem = oi.Id;
        aas.estimatedTax = oi.SBQQ__TaxAmount__c;
        if(OrgSettings.BillingEnabled) {
            // aas.actualTax = (Double) PWUtils.getField(oi, 'blng__BilledTax__c');
        }
        
        req.assetAction = aa;
        req.addPeriod(asp);
        req.assetActionSources.add(aas);

        if(OrgSettings.LogikEnabled && (oi.Modified_Root_Asset__c == null || oi.Modified_Root_Asset__c == oi.SBQQ__Asset__c) && (oi.SBQQ__BundleRoot__c == oi.Id || oi.SBQQ__BundleRoot__c == null) && PWUtils.getField(oi, LOGIK_CONFIG_ID_FIELD) != null) {
            // Root item. add Logik source
            // Tranquility.NonReferencedAssetActionSourceInput aas_logik = new Tranquility.NonReferencedAssetActionSourceInput();
            // aas_logik.quantity = oi.Quantity;
            // aas_logik.productAmount = 0.0;
            // aas_logik.externalReference = (String) PWUtils.getField(oi, LOGIK_CONFIG_ID_FIELD);
            // aas_logik.externalReferenceDataSource = 'Logik Configuration';
            // req.assetActionSources.add(aas_logik);
        } 

        Tranquility.GenerateResult result = new Tranquility.GenerateResult();
        result.oi = oi;
        result.mrrChange = aa.mrrChange;
        result.quantityChange = aa.quantityChange;
        result.amount = aa.amount;
        result.newPeriod = asp;
        result.assetCreated = isNewAsset;
        result.request = req;

        if(mode == PROCESS_MODE.SEND) {
            Tranquility.AssetServiceResponse response = req.send();
            result.asset = (Asset) PWUtils.assign(response.asset, req.getAsset(getAssetFields()));
        } else if (mode == PROCESS_MODE.TASK) {
            AssetManagementProcessTask task = req.generateTask();
            task.addContext('OrderItem', oi);
            task.addContext('isNew', isNewAsset);
            task.after(postInsertAsset);
            queue.add(task);
            result.asset = req.getAsset(getAssetFields());
        }
        return result;
    }

   // @AuraEnabled
   // public static void RecalculateAsset(Asset a, String namedCredential){
   //     if(namedCredential != null) {
   //         staticNamedCredential = namedCredential;
   //     }
   //     // build amount, mrr and ASPs from children
   //     NestedObject root = ConfigurationBOMController.getBOMForAsset(a, null, getAssetFields(), null);
   //     root.rollUp(recalculateRollUp);
   //     a.Recalculate__c = false;
   //     update a;
   // }

    public static Tranquility.CancelResult CancelAsset (Id assetId) {
        Asset a = [SELECT CurrentQuantity, Quantity, CurrentAmount, CurrentMrr, LifecycleStartDate, LifecycleEndDate, (SELECT Quantity FROM AssetStatePeriods), (SELECT ActionDate FROM AssetActions) FROM Asset WHERE Id = :assetId ];
        return CancelAsset(a);
    }

    public static Tranquility.CancelResult CancelAsset (Asset a) {

        if(a.AssetActions.size() == 0) {
            throw new NonCALMAssetException('Non-CALM Asset: no AssetActions present');
        }

        Datetime now = Datetime.now();

        Tranquility.CancelAssetRequest req = new Tranquility.CancelAssetRequest(a.Id, staticNamedCredential);
        Tranquility.AssetActionInput aa = new Tranquility.AssetActionInput();
        Tranquility.NonReferencedAssetActionSourceInput aas = new Tranquility.NonReferencedAssetActionSourceInput();
        Tranquility.AssetStatePeriodInput asp = new Tranquility.AssetStatePeriodInput();

        double qty;
        if(a.CurrentQuantity != null && a.CurrentQuantity > 0) {
            qty = a.CurrentQuantity;
        } else if (a.Quantity != null && a.Quantity > 0) {
            qty = a.Quantity;
        } else {
            qty = a.AssetStatePeriods[0].Quantity;
        }

        aa.category = 'Cancellations';
        aa.actionDate = a.AssetActions[0].ActionDate.addSeconds(1);
        aa.quantityChange = qty;
        aa.mrrChange = a.CurrentMrr;
        aa.amount = a.CurrentAmount;

        asp.startDate = a.LifecycleStartDate;
        asp.endDate = a.LifecycleEndDate;
        asp.mrr = a.CurrentMrr;
        asp.amount = a.CurrentAmount;
        asp.quantity = qty;

        // aas.transactionDate = now;
        // aas.startDate = now;
        // aas.endDate = a.LifecycleEndDate;
        aas.quantity = -1.0 * qty;
        aas.productAmount = -1.0 * a.CurrentAmount;
        aas.externalReference = 'manual';

        req.assetAction = aa;
        req.assetStatePeriod = asp;
        req.assetActionSources.add(aas);

        Tranquility.CancelResult result = new Tranquility.CancelResult();

        if(mode == PROCESS_MODE.SEND) {
            Tranquility.AssetServiceResponse response = req.send();
            result.asset = response.asset;
        } else if (mode == PROCESS_MODE.TASK) {
            AssetManagementProcessTask task = req.generateTask();
            task.after(postCancelAsset);
            queue.add(task);
        }
        return result;
    }

    public static List<Asset> DeleteAllAssetsForAccount (ID accountId) {
        return DeleteAllAssetsForAccount(accountId, null);
    }

    public static List<Asset> DeleteAllAssetsForAccount (ID accountId, String namedCredential) {

        if(namedCredential != null) {
            staticNamedCredential = namedCredential;
        }

        String selectStm = 'SELECT ' + String.join(getAssetFields(), ',') + ' FROM Asset';
        String whereCl = String.format(
            'AccountId = \'\'{0}\'\' OR Aggregate_Asset__r.AccountId = \'\'{0}\'\'',
            new String[]{
                accountId
            }
        );
        List<Asset> toDelete = Database.query(selectStm + ' WHERE ' + whereCl);

        return DeleteAll(toDelete);
    }

    public static List<Asset> DeleteAssetTree(Id assetId, String namedCredential) {

        if(namedCredential != null) {
            staticNamedCredential = namedCredential;
        }
        
        String selectStm = 'SELECT ' + String.join(getAssetFields(), ',') + ' FROM Asset';
        String whereCl = String.format(
            'Id = \'\'{0}\'\' OR ParentId = \'\'{0}\'\' OR RootAssetId = \'\'{0}\'\' OR Aggregate_Asset__c = \'\'{0}\'\' OR Aggregate_Asset__r.ParentId = \'\'{0}\'\' OR Aggregate_Asset__r.RootAssetId = \'\'{0}\'\'',
            new String[]{
                assetId
            }
        );
        List<Asset> toDelete = Database.query(selectStm + ' WHERE ' + whereCl);
        
        return DeleteAll(toDelete);
        
    }

    private static List<Asset> DeleteAll (List<Asset> assets) {
        Account cancelledAssetAcct = [SELECT Id FROM Account WHERE Name LIKE '%DELETED ASSET%'];
        Id cancelledAssetAcctId = null;
        if(cancelledAssetAcct != null) {
            cancelledAssetAcctId = cancelledAssetAcct.Id;
        } else {
            throw new AssetManagementException('Failed to delete. No asset deletion account found.');
        }
        List<SObject> toUpdate = new List<SObject>();
        if(assets.size() == 0) {
            return null;
        }
        String[] assetIds = new String[]{};
        for (Asset a : assets) {
            assetIds.add(a.Id);
        }
        for (Asset a : assets) {
            Asset updateAsset = new Asset(Id=a.Id);
            if(a.HasLifecycleManagement && a.AssetActions[0].Category != 'Cancellations'){
                // Un-cancelled CALM asset
                try {
                    Tranquility.CancelResult result = CancelAsset(a);
                } catch(Exception e) {
                    if(e instanceof NonCALMAssetException) {
                        //do nothing
                    } else {
                        throw e;
                    }
                }
            }
            // if(!a.HasLifecycleManagement || mode == PROCESS_MODE.SEND) {
            updateAsset.AccountId = cancelledAssetAcctId;
            updateAsset.Status = 'Cancelled';
            // }
            if(!assetIds.contains(a.ParentId)) {
                updateAsset.ParentId = null;
            }
            toUpdate.add(updateAsset);
        }
        List<OrderItem> ois = [SELECT Id, Asset__c FROM OrderItem WHERE Asset__c IN :assetIds];
        for (OrderItem oi : ois) {
            oi.Asset__c = null;
        }
        toUpdate.addAll(ois);
        if(mode == PROCESS_MODE.SEND) {
            update toUpdate;
        } else if (mode == PROCESS_MODE.TASK) {
            AssetManagementProcessTask task = new AssetManagementProcessTask(AssetManagementProcessTask.Operation.DML_UPDATE, toUpdate);
            task.before(preUpdateAssets);
            task.addContext('CancelledAssetAccountId', cancelledAssetAcctId);
            queue.add(task);
        }
        return assets;
    }

    private static Asset retrieveAssetForModify(Id assetId) {
        Asset a = [SELECT Id, Name, AccountId, LifecycleStartDate, LifecycleEndDate, RootAssetId, Aggregate_Asset__c FROM Asset WHERE Id = :assetId];
        System.debug(a);
        return a; //[SELECT Id, Name, AccountId, LifecycleStartDate, LifecycleEndDate, RootAssetId, Aggregate_Asset__c FROM Asset WHERE Id = :assetId];
    }

    public static List<SBQQ__QuoteLine__c> ModifyAsset (Id assetId, Datetime dt, Id quoteId, Boolean salesOnly, List<Id> accIds) {
        Asset a = retrieveAssetForModify(assetId);
        SBQQ__Quote__c q = new SBQQ__Quote__c(
            Id=quoteId,
            SBQQ__Type__c='Amendment',
            SBQQ__StartDate__c = dt.date(),
            SBQQ__EndDate__c = Date.valueOf(a.LifecycleEndDate),
            SBQQ__Primary__c = true
        );
        update q;
        return ModifyAsset(a, dt, q, salesOnly, accIds);
    }

    public static SBQQ__Quote__c ModifyAsset (Id assetId, Datetime dt, Id oppId, List<Id> accIds) {
        return ModifyAsset(retrieveAssetForModify(assetId), dt, new Opportunity(Id=oppId), accIds);
    }

    public static SBQQ__Quote__c ModifyAsset (Id assetId, Datetime dt, List<Id> accIds) {
        return ModifyAsset(retrieveAssetForModify(assetId), dt, accIds);
    }

    public static SBQQ__Quote__c ModifyAsset (Asset a) {
        return ModifyAsset(a, null, new List<Id>{a.AccountId});
    }

    public static SBQQ__Quote__c ModifyAsset (Asset a, Datetime dt, List<Id> accIds) {
        Opportunity opp = new Opportunity(
            Name = 'Modify: ' + a.Name,
            AccountId = a.AccountId,
            StageName = 'Qualification',
            CloseDate = Date.today().addMonths(1),
            Pricebook2Id = PWUtils.standardPricebookId
        );
        insert opp;
        return ModifyAsset(a, dt, opp, accIds);
    }

    public static SBQQ__Quote__c ModifyAsset (Asset a, Datetime dt, Opportunity o, List<Id> accIds) {
        if(o == null) {
            return ModifyAsset(a, dt, accIds);
        }
        SBQQ__Quote__c q = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = o.Id,
            SBQQ__Type__c = 'Amendment',
            SBQQ__StartDate__c = dt.date(),
            SBQQ__EndDate__c = Date.valueOf(a.LifecycleEndDate),
            SBQQ__Primary__c = true,
            SBQQ__Account__c = a.AccountId,
            SBQQ__PricebookId__c = PWUtils.standardPricebookId,
            SBQQ__Pricebook__c = PWUtils.standardPricebookId
        );
        insert q;
        q.SBQQ__Account__c = a.AccountId;
        update q;
        ModifyAsset(a, dt, q, true, accIds);
        return q;
    }

    // public static List<SBQQ__Quote__c> ModifyAsset (Asset a, Datetime dt, SBQQ__Quote__c, Boolean saveQuoteLines) {
    //     // Retrieve assets
    // }

    public static List<SBQQ__QuoteLine__c> ModifyAsset (Asset a, Datetime dt, SBQQ__Quote__c q, Boolean saveQuoteLines, List<Id> accountIds) {
        /**
         * 1. Find root asset
         * 2. Retrieve Logik ID
         * 3. Retrieve all active assets for root
         * 4. Map each asset to quote line
         * 5. Save and return quote lines
         */

        

        if(dt == null) {
            dt = Datetime.now();
        }
        Integer count = 0;
        Long timestamp = Datetime.now().getTime();

        String fmtDt = dt.format('yyyy-MM-dd\'T\'HH:mm:ssZ');
        List<String> assetFields = new String[]{
            '(SELECT Quantity FROM AssetStatePeriods WHERE StartDate < ' + fmtDt + ' AND EndDate >= ' + fmtDt + ')'
        };
        
        String whereClause;
        // TODO: filter on active/non-cancelled assets
        if(a.Aggregate_Asset__c != null) {
            whereClause = 'Id = \'' + a.RootAssetId + '\'';
        } else if (accountIds != null) {
            whereClause = 'Aggregate_Asset__c = \'' + a.RootAssetId + '\' AND AccountId IN (\'' + String.join(accountIds, ',') + '\')';
        }  else {
            whereClause = 'Aggregate_Asset__c = \'' + a.RootAssetId + '\'';
        }

        List<Asset> rootAssets = PWUtils.selectStar('Asset', whereClause, assetFields);
        System.debug('RootAssets:\n' + JSON.serialize(rootAssets));
        List<SBQQ__QuoteLine__c> qls = new List<SBQQ__QuoteLine__c>();
        Map<Id,Id> childToParent = new Map<Id,Id>();
        Boolean assetExists = false;
        for (Asset rootAsset : rootAssets) {
            if(rootAsset.AssetStatePeriods.size() == 0) {
                // throw new InvalidDateException('Modify date is not valid for the root asset. Please ensure modify date is within the lifecycle of the asset.');
                continue;
            }
            assetExists = true;
            SBQQ__QuoteLine__c rootQl = new SBQQ__QuoteLine__c(
                InternalId__c = timestamp + '|' + count++
            );
            PWUtils.twinFields(rootAsset, rootQl, new String[]{'Name'});
            rootQl.SBQQ__Product__c = rootAsset.Product2Id;
            rootQl.SBQQ__UpgradedAsset__c = rootAsset.Id;
            rootQl.SBQQ__Quote__c = q.Id;
            rootQl.SBQQ__Quantity__c = rootAsset.AssetStatePeriods[0].Quantity;
            rootQl.SBQQ__PriorQuantity__c = rootAsset.AssetStatePeriods[0].Quantity;
            rootQl.SBQQ__Existing__c = true;
            rootQl.SBQQ__Incomplete__c = true; //triggers re-calculation
            rootQl.Account__c = a.AccountId;
            rootQl.Site__c = rootAsset.AccountId;

            if(OrgSettings.LogikEnabled) { // TODO: replace with getAssetConfigId
                // AssetActionSource aas = [SELECT ExternalReference FROM AssetActionSource WHERE ExternalReferenceDataSource = 'Logik Configuration' AND AssetAction.AssetId = :rootAsset.Id AND AssetAction.ActionDate < :dt ORDER BY AssetAction.ActionDate DESC LIMIT 1];
                // if(aas != null) {
                //     PWUtils.setField(rootQl, 'LGK__Logik_Id__c', aas.ExternalReference);
                // }
            }

            
            whereClause = 'RootassetId = \'' + rootAsset.Id + '\' AND Status != \'Cancelled\'';
            List<Asset> assets = PWUtils.selectStar('Asset', whereClause, assetFields);
            List<Id> prodIds = new List<Id>{rootAsset.Product2Id};
            for (Asset assetIter : assets) {
                prodIds.add(assetIter.Product2Id);
            }
            List<PricebookEntry> pbes = [SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = :PWUtils.standardPricebookId AND Product2Id IN :prodIds];
            Map<Id,Id> prodIdToPbeId = new Map<Id,Id>();
            for (PricebookEntry pbe : pbes) {
                prodIdToPbeId.put(pbe.Product2Id, pbe.Id);
            }
            rootQl.SBQQ__PricebookEntryId__c = prodIdToPbeId.get(rootAsset.Product2Id);
            System.debug('ASSETS:\n'+JSON.serialize(assets));

            // List<AssetStatePeriod> asps = [SELECT AssetId, Quantity, Asset.Product2Id, Asset.SBQQ__DynamicOptionId__c FROM AssetStatePeriod WHERE StartDate < :dt AND EndDate >= :dt AND Asset.RootAssetId = :rootAsset.Id AND Asset.Status != 'Cancelled'];
            // List<Asset> assets = [SELECT Id, Product2Id, CurrentQuantity, (SELECT Quantity FROM AssetStatePeriods WHERE StartDate < :d AND EndDate >= :d) FROM Asset WHERE RootAssetId = :rootAsset.Id AND Status = 'Shipped'];
            
            
            qls.add(rootQl);
            NestedObject assetBOM = new NestedObject(assets, 'Id', 'ParentId');
            for (NestedObject node : assetBOM.all()) {
                Asset asset = (Asset) node.obj;
                if(asset.Id == rootAsset.Id) {
                    continue;
                }
                if(asset.AssetStatePeriods.size() == 0) {
                    continue;
                }

                SBQQ__QuoteLine__c ql = new SBQQ__QuoteLine__c(
                    InternalId__c = timestamp + '|' + count++
                );

                PWUtils.twinFields(asset, ql, new String[]{'Name'});
                ql.SBQQ__Product__c = asset.Product2Id;
                ql.SBQQ__UpgradedAsset__c = asset.Id;
                ql.SBQQ__Quote__c = q.Id;
                ql.SBQQ__PriorQuantity__c = asset.AssetStatePeriods[0].Quantity;
                ql.SBQQ__Quantity__c = asset.AssetStatePeriods[0].Quantity;
                ql.SBQQ__Existing__c = true;
                ql.SBQQ__OptionType__c = 'Component';
                ql.SBQQ__Incomplete__c = true; // triggers re-calculation
                ql.SBQQ__AllowAssetRefund__c = true;
                ql.Account__c = a.AccountId;
                ql.Site__c = ((Asset)node.obj).AccountId;
                ql.SBQQ__PricebookEntryId__c = prodIdToPbeId.get(asset.Product2Id);
                
                childToParent.put(asset.Id, asset.ParentId);
                qls.add(ql);
            }
        }
        if(!assetExists) {
            throw new InvalidDateException('Modify date is not valid for the root asset. Please ensure modify date is within the lifecycle of the asset.');
        }
        if(saveQuoteLines == true) {
            System.debug('QUOTE LINES:\n'+JSON.serialize(qls));
            insert qls;
            List<SBQQ__QuoteLine__c> toUpdateQls = new List<SBQQ__QuoteLine__c>();
            for (SBQQ__QuoteLine__c ql : qls) {
                for (SBQQ__QuoteLine__c qll: qls) {
                    if(qll.SBQQ__UpgradedAsset__c == childToParent.get(ql.SBQQ__UpgradedAsset__c)) {
                        if(qll.InternalId__c == null) {
                            throw new AssetManagementException('InternalId__c not set for parent.');
                        }
                        toUpdateQls.add(
                            new SBQQ__QuoteLine__c(
                                Id=ql.Id,
                                SBQQ__RequiredBy__r=new SBQQ__QuoteLine__c(InternalId__c=qll.InternalId__c)
                            )
                        );
                    }
                }
            }
            update toUpdateQls;
        }
        return qls;
    }

    public static String getAssetConfigId(ID assetId, Datetime asOf) {
        if(!OrgSettings.LogikEnabled) {
            return null;
        }
        // AssetActionSource aas = [SELECT ExternalReference FROM AssetActionSource WHERE ExternalReferenceDataSource = 'Logik Configuration' AND AssetAction.AssetId = :assetId AND AssetAction.ActionDate <= :asOf ORDER BY AssetAction.ActionDate DESC LIMIT 1];
        // if(aas != null) {
        //     return aas.ExternalReference;
        // }
        return null;
    }

    public static void InitiateAsset (Asset a, Id orderItemId) {
        OrderItem oi = (OrderItem) PWUtils.selectStar('OrderItem', 'Id = \'' + orderItemId + '\'')[0];
        if(oi.SBQQ__QuoteLine__c != null) {
            SBQQ__QuoteLine__c ql = (SBQQ__QuoteLine__c) PWUtils.selectStar('SBQQ__QuoteLine__c', 'Id = \'' + oi.SBQQ__QuoteLine__c + '\'')[0];
            PWUtils.twinFields(ql, a, new String[]{'Name'});
        }
        PWUtils.twinFields(oi, a, new String[]{'Name'});
    }

    public static Asset Aggregate(List<AggregateAssetInput> inputs, Id aggAccId){ 
        Tranquility.UpsertAssetRequest req;
        Asset baseAsset = inputs[0].assetAction.Asset;
        Double totalAmountChange = 0.0;
        Double totalMrrChange = 0.0;
        Double totalQuantityChange = 0.0;
        Boolean newAggAsset = false;
        String category = inputs[0].assetAction.CategoryEnum;
        Datetime aDate = inputs[0].assetAction.ActionDate;
        List<Asset> toUpdate = new List<Asset>();
        if(baseAsset.Aggregate_Asset__c == null) {
            // create new asset
            newAggAsset = true;
            req = new Tranquility.GenerateAssetRequest(staticNamedCredential);
            ((Tranquility.GenerateAssetRequest)req).accountId = aggAccId;
            ((Tranquility.GenerateAssetRequest)req).assetName = baseAsset.Name;
            ((Tranquility.GenerateAssetRequest)req).productId = baseAsset.Product2Id;
            ((Tranquility.GenerateAssetRequest)req).currencyIsoCode = inputs[0].currencyIsoCode;
        } else {
            req = new Tranquility.ChangeAssetRequest(baseAsset.Aggregate_Asset__c, staticNamedCredential);
        }
        List<Tranquility.TimePeriod> rawPeriods = new List<Tranquility.TimePeriod>();
        List<Id> allSourceIds = new List<Id>();
        for (AggregateAssetInput input : inputs) {
            if(input.assetAction.Asset.Aggregate_Asset__c != baseAsset.Aggregate_Asset__c) {
                // throw error
                throw new AssetManagementException('Mismatch in aggregate asset id.');
            }
            if(input.assetAction.Asset.Product2Id != baseAsset.Product2Id) {
                throw new AssetManagementException('Mismatch in aggregate asset product.');
            }
            for (AssetStatePeriod asp : input.assetStatePeriods) {
                rawPeriods.add(new Tranquility.TimePeriod(asp, input.sourceIds));
            }
            totalAmountChange+=input.assetAction.Amount;
            totalMrrChange+=input.assetAction.MrrChange;
            totalQuantityChange+=input.assetAction.QuantityChange;
            allSourceIds.addAll(input.sourceIds);
            if(category != 'Other' && category != input.assetAction.CategoryEnum) {
                // If mixed category, change to 'Other'
                category = 'Other';
            }
            if(input.assetAction.ActionDate < aDate) {
                // Set to earliest date
                aDate = input.assetAction.ActionDate;
            }
            toUpdate.add(input.assetAction.Asset);
        }
        List<Tranquility.TimePeriod> normalizedPeriods = Tranquility.normalizeTimePeriods(rawPeriods);
        for (Tranquility.TimePeriod period : normalizedPeriods) {
            req.addPeriod(new Tranquility.AssetStatePeriodInput(period));
        }
        Tranquility.AssetActionInput aa = new Tranquility.AssetActionInput();
        aa.amount = totalAmountChange;
        aa.quantityChange = totalQuantityChange;
        aa.mrrChange = totalMrrChange;
        aa.category = category;
        aa.actionDate = aDate;
        req.assetAction = aa;
        if(mode == PROCESS_MODE.SEND) {
            Tranquility.AssetServiceResponse resp = req.send();
            return resp.asset;
        } else if (mode == PROCESS_MODE.TASK) {
            AssetManagementProcessTask task = req.generateTask();
            task.after(new PostInsertAggregateAsset(toUpdate));
            queue.add(task);
            return req.getAsset(getAssetFields());
        }
        return null;
    }

    public static List<Asset> AggregateAll (List<Tranquility.GenerateResult> results) {
        System.debug('Aggregating assets...\n'+JSON.serialize(results));
        List<Asset> aggAssets = new List<Asset>();
        Map<Id,Map<Id,List<AggregateAssetInput>>> aggJobs = new Map<Id,Map<Id,List<AggregateAssetInput>>>();
        for (Tranquility.GenerateResult result : results) {
            Id accId = result.oi.Order.AccountId;
            Map<Id,List<AggregateAssetInput>> accJobs = aggJobs.get(accId);
            if(accJobs == null) {
                accJobs = new Map<Id,List<AggregateAssetInput>>();
            }
            List<AggregateAssetInput> prodJobs = accJobs.get(result.asset.Product2Id);
            if(prodJobs == null) {
                prodJobs = new List<AggregateAssetInput>();
            }
            prodJobs.add(new AggregateAssetInput(result));
            accJobs.put(result.asset.Product2Id, prodJobs);
            aggJobs.put(accId, accJobs);
        }
        for(Id accId : aggJobs.keySet()) {
            for(Id prodId : aggJobs.get(accId).keySet()) {
                aggAssets.add(Aggregate(aggJobs.get(accId).get(prodId), accId));
            }
        }
        if(mode == PROCESS_MODE.SEND) {
            //TODO
        } else if (mode == PROCESS_MODE.TASK) {
            AssetManagementProcessTask task = new AssetManagementProcessTask(AssetManagementProcessTask.Operation.DML_UPDATE, new List<SObject>());
            task.before(preUpdateAggregateAssets);
            queue.add(task);
        }
        allTouchedAssets.addAll(aggAssets);
        return aggAssets;
    }

    public static List<Asset> UpdateAssetsOnOrderFinalisation (Id orderId, String namedCredential) {
        if(namedCredential != null) {
            staticNamedCredential = namedCredential;
        }
        List<Asset> assetResults = new List<Asset>();
        List<Asset> toUpdate = new List<Asset>();
        String closedOiQuery = 'OrderId = \'' + orderId + '\' AND SBQQ__Status__c = \'Delivered & Accepted\' AND Asset__c != null';
        List<OrderItem> closedOis = Database.query('SELECT ' + String.join(getOrderItemFields(), ',') + ' FROM OrderItem WHERE ' + closedOiQuery);
        for (OrderItem oi : closedOis) {

            if(oi.ServiceDate != oi.Initial_Start_Date__c) {
                Tranquility.ChangeAssetRequest req = new Tranquility.ChangeAssetRequest(oi.Asset__c, staticNamedCredential);
                Tranquility.AssetActionInput aa = new Tranquility.AssetActionInput();
                Tranquility.ReferencedAssetActionSourceInput aas = new Tranquility.ReferencedAssetActionSourceInput();
                
                List<Tranquility.AssetStatePeriodInput> toAdd = new List<Tranquility.AssetStatePeriodInput>();
                Tranquility.AssetStatePeriodInput targetedPeriod = req.getStateForTime(oi.Initial_Start_Date__c);
                Tranquility.AssetStatePeriodInput periodBefore;
                Double mrr = 0.0;
                Double amount = 0.0;
                Double quantity = 0.0;
                for (Tranquility.AssetStatePeriodInput pd : req.getCurrentPeriods()) {
                    if(pd.equals(targetedPeriod)) {
                        if(periodBefore != null) {
                            mrr = periodBefore.mrr;
                            amount = periodBefore.amount;
                            quantity = periodBefore.quantity;
                        }
                        Tranquility.AssetStatePeriodInput replPeriod = pd.clone();
                        replPeriod.mrr = mrr;
                        replPeriod.amount = amount;
                        replPeriod.quantity = quantity;
                        req.addPeriod(replPeriod);
                        break;
                    }
                    periodBefore = pd;
                }

                Tranquility.AssetStatePeriodInput finalAsp = new Tranquility.AssetStatePeriodInput();
                finalAsp.startDate = oi.ServiceDate;
                finalAsp.endDate = oi.EndDate;
                finalAsp.mrr = mrr + getMrr(oi);
                finalAsp.amount = amount + getAmount(oi); // TODO;
                finalAsp.quantity = amount + oi.Quantity;
                req.addPeriod(finalAsp);

                aa.category = 'Other'; // TODO
                aa.actionDate = Date.today();
                aa.quantityChange = 0;
                aa.mrrChange = 0;
                aa.amount = 0;

                aas.transactionDate = Date.today();
                aas.referenceEntityItem = oi.Id;

                req.assetAction = aa;
                req.assetActionSources = new List<Tranquility.AssetActionSourceInput>{
                    aas
                };

                Tranquility.GenerateResult result = new Tranquility.GenerateResult();
                if(mode == PROCESS_MODE.SEND) {
                    Tranquility.AssetServiceResponse response = req.send();
                    result.asset = (Asset) PWUtils.assign(response.asset, req.getAsset(getAssetFields()));
                } else if (mode == PROCESS_MODE.TASK) {
                    AssetManagementProcessTask task = req.generateTask();
                    // ...
                    result.asset = req.getAsset(getAssetFields());
                    queue.add(task);
                }
                assetResults.add(result.asset);
            }
            toUpdate.add(new Asset(
                Id = oi.Asset__c,
                Status = 'Installed'
            ));
        }

        if(toUpdate.size() > 0) {
            if(mode == PROCESS_MODE.SEND) {
                update toUpdate;
            } else if (mode == PROCESS_MODE.TASK) {
                queue.add(new AssetManagementProcessTask(
                    AssetManagementProcessTask.Operation.DML_UPDATE, toUpdate
                ));
            }
        }
        return assetResults;
    }
    

    // Exceptions
    private class AssetManagementException extends Exception {}

    public class NonCALMAssetException extends Exception {}

    private class InvalidDateException extends Exception {}

    
    /**
     * @class RollUpAfterDescendantChanges
     * @description implementation of NestedObject.RollUpFunction to perform more complex roll-up after changes to existing assets.
     *      This function handles generation of new ASPs and AASs to account for changes to descendant assets.
     */
    private inherited sharing class RollUpAfterDescendantChanges implements NestedObject.RollUpFunction {
        public void forEach(NestedObject no, List<NestedObject> children) {
            // Build list of time periods for changed children
            List<Tranquility.TimePeriod> changedPeriods = new List<Tranquility.TimePeriod>();
            for (NestedObject child : children) {
                Boolean isChanged = (Boolean) child.getData('changed');
                if(isChanged != null && isChanged) {
                    // child has been changed. Build a new parent period for this newly-added/changed child preiod.
                    Tranquility.TimePeriod period = new Tranquility.TimePeriod();
                    // period.startDate = Datetime.valueOfGmt(child.getSFlag('newPeriodStart'));
                    // period.endDate = Datetime.valueOfGmt(child.getSFlag('newPeriodEnd'));
                    period.startDate = (Datetime) child.getData('newPeriodStart');
                    period.endDate = (Datetime) child.getData('newPeriodEnd');
                    if(!changedPeriods.contains(period)) {
                        // child period is not already accounted for in the new parent periods.
                        period.sourceIds.add((String) child.getData('OrderItem.Id'));
                        period.setValue('mrr', (Double) child.getData('mrr'));
                        period.setValue('amount', (Double) child.getData('amount'));
                        changedPeriods.add(period);
                    } else {
                        // child period is already in the parent periods--find it and add this child's source id
                        for(Tranquility.TimePeriod changedPeriod : changedPeriods) {
                            if(changedPeriod == period) {
                                changedPeriod.sourceIds.add((String) child.getData('OrderItem.Id'));
                                changedPeriod.setValue(
                                    'mrr',
                                    changedPeriod.getValue('mrr') + (Double) child.getData('mrr')
                                );
                                changedPeriod.setValue(
                                    'amount',
                                    changedPeriod.getValue('amount') + (Double) child.getData('amount')
                                );
                            }
                        }
                    }
                    // SM 2022-10-19
                    ((Asset)child.obj).ParentId = child.parentId;
                }
            }
            if(changedPeriods.size() == 0) {
                // This parent has no changed children.
                return;
            }
            Tranquility.ChangeAssetRequest req = new Tranquility.ChangeAssetRequest(no.obj.getId(), staticNamedCredential);
            List<Id> sourceIds = new List<Id>();
            Double totalMrrChange = 0.0;
            Double totalAmtChange = 0.0;
            List<Tranquility.TimePeriod> normalizedPeriods = Tranquility.normalizeTimePeriods(changedPeriods);
            List<Tranquility.AssetActionSourceInput> aasList = new List<Tranquility.AssetActionSourceInput>();
            for (Tranquility.TimePeriod period : normalizedPeriods) { // This could be done in the loop above to avoid the SOQL
                AggregateResult res = [SELECT SUM(Amount) totalAmount, SUM(Mrr) totalMrr FROM AssetStatePeriod WHERE Asset.ParentId = :no.obj.getId() AND StartDate <= :period.startDate AND EndDate >= :period.endDate];
                Tranquility.AssetStatePeriodInput asp = new Tranquility.AssetStatePeriodInput();
                Tranquility.AssetStatePeriodInput current = req.getStateForTime(period.startDate);
                asp.startDate = period.startDate;
                asp.endDate = period.endDate;
                
                asp.mrr = (Double) res.get('totalMrr') + period.getValue('mrr'); // new period not yet added to DB so add value here
                asp.amount = (Double) res.get('totalAmount') + period.getValue('amount'); // new period not yet added to DB so add value here
                asp.quantity = current.quantity;
                req.addPeriod(asp);
                sourceIds.addAll(period.sourceIds);
                totalMrrChange += asp.mrr - current.mrr;
                totalAmtChange += asp.amount - current.amount;

                for (Id sourceId : period.sourceIds) {
                    Tranquility.ReferencedAssetActionSourceInput aas = new Tranquility.ReferencedAssetActionSourceInput();
                    aas.quantity = current.quantity;
                    aas.productAmount = asp.amount;
                    aas.referenceEntityItem = sourceId;
                    aasList.add(aas);
                }
            }
            Tranquility.AssetActionInput aa = new Tranquility.AssetActionInput();
            aa.category = 'Upsells';
            aa.actionDate = normalizedPeriods[0].startDate;
            aa.quantityChange = 0;
            aa.mrrChange = totalMrrChange;
            aa.amount = totalAmtChange;
            req.assetAction = aa;
            req.assetActionSources = aasList;
            no.setData('changed', true);
            if(mode == PROCESS_MODE.SEND) {
                Tranquility.AssetServiceResponse result = req.send();
            } else if (mode == PROCESS_MODE.TASK) {
                AssetManagementProcessTask task = req.generateTask();
                task.addContext('isNew', false);
                // task.after(postUpdateAssets);
                queue.add(task);
            }
        }
    }

    /**
     * @class RollUpAsset
     * @description implementation of NestedObject.RollUpFunction to perform more complex roll-up after changes to existing assets.
     *      This function handles generation of new ASPs and AASs to account for changes to descendant assets.
     */
    // private inherited sharing class RollUpAsset implements NestedObject.RollUpFunction {
    //     public void forEach(NestedObject no, List<NestedObject> children) {
    //         // Build list of time periods for changed children
    //         List<Tranquility.TimePeriod> periods = new List<Tranquility.TimePeriod>();
    //         for (NestedObject child : children) {
    //             for (AssetStatePeriod asp : ((Asset) child.obj).AssetStatePeriods) {
    //                 Tranquility.TimePeriod period = new Tranquility.TimePeriod(asp);
    //                 if(!periods.contains(period)) {
    //                     // child period is not already accounted for in the new parent periods.
    //                     // period.sourceIds.add((String) child.getData('OrderItem.Id'));
    //                     periods.add(period);
    //                 } else {
    //                     // child period is already in the parent periods--find it and add this child's source id
    //                     /*
    //                     for(Tranquility.TimePeriod per : periods) {
    //                         if(per == period) {
    //                             per.sourceIds.add((String) child.getData('OrderItem.Id'));
    //                         }
    //                     }
    //                     */
    //                 }
    //             }
    //             // Build a new parent period for this newly-added/changed child preiod.
    //         }
    //         if(periods.size() == 0) {
    //             // This parent has no children.
    //             return;
    //         }
    //         Tranquility.ChangeAssetRequest req = new Tranquility.ChangeAssetRequest(no.obj.Id, staticNamedCredential);
    //         List<Id> sourceIds = new List<Id>();
    //         Double totalMrrChange = 0.0;
    //         Double totalAmtChange = 0.0;
    //         List<Tranquility.TimePeriod> normalizedPeriods = Tranquility.normalizeTimePeriods(periods);
    //         List<Tranquility.AssetActionSourceInput> aasList = new List<Tranquility.AssetActionSourceInput>();
    //         for (Tranquility.TimePeriod period : normalizedPeriods) { // This could be done in the loop above to avoid the SOQL
    //             AggregateResult res = [SELECT SUM(Amount) totalAmount, SUM(Mrr) totalMrr FROM AssetStatePeriod WHERE Asset.ParentId = :no.obj.Id AND StartDate <= :period.startDate AND EndDate >= :period.endDate];
    //             Tranquility.AssetStatePeriodInput asp = new Tranquility.AssetStatePeriodInput();
    //             Tranquility.AssetStatePeriodInput current = req.getStateForTime(period.startDate);
    //             asp.startDate = period.startDate;
    //             asp.endDate = period.endDate;
    //             asp.mrr = (Double) res.get('totalMrr');
    //             asp.amount = (Double) res.get('totalAmount');
    //             asp.quantity = current.quantity;
    //             req.addPeriod(asp);
    //             sourceIds.addAll(period.sourceIds);
    //             totalMrrChange += asp.mrr - current.mrr;
    //             totalAmtChange += asp.amount - current.amount;
    // 
    //             for (Id sourceId : period.sourceIds) {
    //                 Tranquility.ReferencedAssetActionSourceInput aas = new Tranquility.ReferencedAssetActionSourceInput();
    //                 aas.quantity = current.quantity;
    //                 aas.productAmount = asp.amount;
    //                 aas.referenceEntityItem = sourceId;
    //                 aasList.add(aas);
    //             }
    //         }
    //         if(!req.periodsChanged()) {
    //             System.debug('Recalculation completed with no changes.');
    //             return;
    //         }
    //         Tranquility.AssetActionInput aa = new Tranquility.AssetActionInput();
    //         aa.category = 'Other'; // TODO - better characterise this
    //         aa.actionDate = normalizedPeriods[0].startDate;
    //         aa.quantityChange = 0;
    //         aa.mrrChange = totalMrrChange;
    //         aa.amount = totalAmtChange;
    //         AssetAction aas = [SELECT Id, ActionDate FROM AssetAction WHERE AssetId = :no.obj.Id AND ActionDate <= :aa.actionDate ORDER BY ActionDate DESC LIMIT 1];
    //         if (aas != null) {
    //             aa.actionDate = aas.ActionDate.addSeconds(1);
    //         }
    //         req.assetAction = aa;
    //         req.assetActionSources = aasList;
    // 
    //         Tranquility.AssetServiceResponse result = req.send();
    //         // no.setData('changed', true);
    //     }
    // }

    /**
     * @class RollUpBeforeInsert
     * @description implementation of NestedObject.RollUpFunction to perform a simple roll up for net-new assets.
     */
    private inherited sharing class RollUpBeforeInsert implements NestedObject.RollUpFunction {
        public void forEach(NestedObject no, List<NestedObject> children) {
            OrderItem oi = (OrderItem) no.obj;
            Double amount = oi.TotalPrice;
            Double mrr = 0.0;
            if(oi.SBQQ__SubscriptionTerm__c != null) {
                mrr = oi.TotalPrice / oi.SBQQ__SubscriptionTerm__c;
            }
            for (NestedObject child : children) {
                OrderItem childOi = (OrderItem) child.obj;
                // Retrieve child amount from node data; set from oi if not present.
                Double childAmount = (Double) child.getData('amount');
                // if(childAmount == null) {
                //     childAmount = childOi.TotalPrice;
                //     child.setData('amount', childAmount);
                // }
                amount += childAmount;
                // Retrieve child mrr from node data; set from oi if not present.
                Double childMrr = (Double) child.getData('mrr');
                // if(childMrr == null) {
                //     if(childOi.SBQQ__SubscriptionTerm__c != null) {
                //         childMrr = (childOi.TotalPrice / childOi.SBQQ__SubscriptionTerm__c);
                //     } else {
                //         childMrr = 0.0;
                //     }
                //     child.setData('mrr', childMrr);
                // }
                mrr += childMrr;
                /*
                OrderItem childOi = (OrderItem) child.obj;
                Double componentTotal = 0.0;
                Double componentMrr = 0.0;
                if (oi.ComponentTotal__c != null) {
                    componentTotal = oi.ComponentTotal__c;
                }
                Double oiMRR = (Double) PWUtils.getField(oi, 'MRR__c');
                Double oiLineMRR = (Double) PWUtils.getField(oi, 'Line_MRR__c');
                if(oiLineMRR == null) {
                    oiLineMrr = 0.0;
                }
                if (oiMRR != null) {
                    componentMrr = oiMRR;
                }
                Double lineAmount;
                try {
                    lineAmount = (Double) PWUtils.getField(oi, 'AdjustedLineAmount');
                } catch (PWUtils.DescribeException e) {
                    lineAmount = oi.TotalPrice;
                }
                amount += lineAmount + componentTotal;
                mrr += oiLineMrr + componentMrr;
                */
            }
            no.setData('mrr', mrr); 
            no.setData('amount', amount);
            // oi.ComponentTotal__c = amount;
            // PWUtils.setField(oi, 'MRR__c', mrr);
            // oi.MRR__c = mrr;
        }   
    }

    // private class ChangedFilterFunction implements NestedObject.FilterFunction {
    //     public Boolean test (SObject obj, Map<String, Object> data) {
    //         return data.containsKey('changed') && (Boolean) data.get('changed');
    //     }
    // }

    private class CreatedFilterFunction implements NestedObject.FilterFunction {
        public Boolean test (NestedObject.Nestable obj, Map<String, Object> data) {
            return data.containsKey('created') && (Boolean) data.get('created');
        }
    }

    private class IsOrderItemFilterFunction implements NestedObject.FilterFunction {
        public Boolean test (NestedObject.Nestable obj, Map<String, Object> data) {
            return ((NestedObject.NestableSObject) obj).obj instanceof OrderItem;
        }
    }

    private class AssignOrderItemToAsset implements NestedObject.AssignFunction {
        private List<Asset> touchedAssets = new List<Asset>();
        private List<Tranquility.GenerateResult> results = new List<Tranquility.GenerateResult>();
        public List<Asset> getAssets() {
            System.debug('Touched Assets:\n' + JSON.serialize(this.touchedAssets));
            return this.touchedAssets;
        }
        public List<Tranquility.GenerateResult> getResults() {
            return this.results;
        }
        public NestedObject.AssignResult assign(NestedObject.Nestable targetObj, NestedObject.Nestable sourceObj, Map<String, Object> data) {
            if(!(((NestedObject.NestableSObject) sourceObj).obj instanceof OrderItem)) {
                return new NestedObject.AssignResult(targetObj, data);
            }
            OrderItem oi = (OrderItem) ((NestedObject.NestableSObject) sourceObj).obj;
            Double mrr = (Double) data.get('mrr');
            if(mrr == null) {
                mrr = 0;
                if(oi.SBQQ__SubscriptionTerm__c != null) {
                    mrr = oi.TotalPrice / oi.SBQQ__SubscriptionTerm__c;
                }
                data.put('mrr', mrr);
            }
            Double amount = (Double) data.get('amount');
            if(amount == null) {
                amount = oi.TotalPrice;
                data.put('amount', amount);
            }
            Tranquility.GenerateResult result = GenerateFromOrderItem(oi, null, mrr, amount);
            this.touchedAssets.add(result.asset);
            this.results.add(result);
            if(targetObj == null) {
                data.put('created', true);
            }
            data.put('changed', true);
            data.put('OrderItem.Id', oi.Id);
            oi_idToSObj.put(oi.Id, oi);
            data.put('newPeriodStart', result.newPeriod.startDate);
            data.put('newPeriodEnd', result.newPeriod.endDate);
            // data.put('newPeriodStart', result.newPeriod.startDate + '');
            // data.put('newPeriodEnd', result.newPeriod.endDate + '');
            return new NestedObject.AssignResult(result.asset, data);
        }
    }

    // PROCESSING HOOKS

    // private class PreInsertAsset implements AssetManagementProcessTask.PreProcessingHook {
    //     public void process(AssetManagementProcessTask task, Map<String,Object> processData) {
    //         
    //     }
    // }

    private class PreUpdateAssets implements AssetManagementProcessTask.PreProcessingHook {
        // Retrieve any missing asset ids that have been recently created
        public void process(AssetManagementProcessTask task, Map<String,Object> processData) {
            System.assertEquals(task.op, AssetManagementProcessTask.Operation.DML_UPDATE);
            List <OrderItem> toUpdate_oi = new List<OrderItem>();
            // retrieve parent
            Map<String,String> assetToOi = (Map<String,String>) processData.get('AssetToOrderItem');
            Map<String,String> assetIdToParent = (Map<String,String>) PWUtils.getSetFromMap(processData, 'AssetIdToParentId', new Map<String,String>());
            Map<Id,Id> oiIdToParentAssetId = (Map<Id,Id>) PWUtils.getSetFromMap(processData, 'OrderItemIdToParentAssetId', new Map<Id,Id>());
            List<String> newAssetIds = (List<String>) processData.get('NewAssetIds');
            if(newAssetIds != null && assetToOi != null) {
                Map<String,String> oiToParent = (Map<String,String>) processData.get('OrderItemToParent');
                Map<String,String> oiToAsset = (Map<String,String>) processData.get('OrderItemToAsset');
                for (String assetId : newAssetIds) {
                    Asset newAsset = new Asset(Id=assetId);
                    String oiId = assetToOi.get(assetId);
                    if(oiId != null) {
                        String parentAssetId = oiIdToParentAssetId.get(oiId);
                        if(parentAssetId == null) {
                            String parentOiId = oiToParent.get(oiId);
                            parentAssetId = oiToAsset.get(parentOiId);
                        }
                        newAsset.ParentId = parentAssetId;
                        newAsset.Status = 'Purchased';
                        toUpdate_oi.add(new OrderItem(Id=oiId, Asset__c=assetId));
                        InitiateAsset(newAsset, oiId);
                        assetIdToParent.put(assetId, parentAssetId);
                    }
                    task.records.add(newAsset);
                }
            }
            List<String> updatedAssetIds = (List<String>) processData.get('UpdatedAssetIds');
            if(updatedAssetIds != null) {
                for (String assetId : updatedAssetIds) {
                    task.records.add(
                        new Asset(
                            Id=assetId,
                            Status = 'Purchased'
                        )
                    );
                }
            }
            // List<String> cancelledAssetIds = (List<String>) processData.get('CancelledAssetIds');
            // if(cancelledAssetIds != null) {
            //     for (String assetId : cancelledAssetIds) {
            //         task.records.add(new Asset(Id=assetId, Status='Cancelled', AccountId=(String) task.getContext('CancelledAssetAccountId')));
            //     }
            // }
            task.records.addAll(toUpdate_oi);
        }
    }

    // private class PreAggregateAssets implements AssetManagementProcessTask.PreProcessingHook {
    //     public void process(AssetManagementProcessTask task, Map<String,Object> processData) {
    //         System.assertEquals(AssetManagementProcessTask.TaskType.CALLOUT,task.type);
    //         List<String> newAssetIds = (List<String>) processData.get('NewAssetIds');
    //         List<Asset> touchedAssets = (List<Asset>) processData.get('TouchedAssets');
    //         if(touchedAssets != null) {
    //             for (Asset touchedAsset : touchedAssets) {
    //                 Asset a = (Asset) PWUtils.find(task.records, findMatchingAsset);
    //                 if(a == null) { // The aggregated record should be created and stored
    //                     throw new AssetManagementException('Aggregate asset Id cannot be found.');
    //                 } else {
    //                     a.Id = touchedAsset.Id;
    //                 }
    //             }
    //         } else {
    //             throw new AssetManagementException('Error when preparing asset aggregation update: no asset data found.');
    //         }
    //     }
    // }

    // private class PreUpdateOrderItems  implements AssetManagementProcessTask.PreProcessingHook {
    //     public void process(AssetManagementProcessTask task, Map<String,Object> processData) {
    //         Map<String,String> oiToAsset = (Map<String,String>) processData.get('OrderItemToAsset');
    //         for (OrderItem oi : (List<OrderItem>) task.records) {
    //             if(oi.Asset__c == null) {
    //                 oi.Asset__c = oiToAsset.get(oi.Id);
    //             }
    //         }
    //     }
    // }

    private class PostInsertAsset implements AssetManagementProcessTask.PostProcessingHook {
        public void process(AssetManagementProcessTask task, AssetManagementProcessTask.Result result, Map<String,Object> processData) {
            System.assertEquals(AssetManagementProcessTask.TaskType.CALLOUT, task.type);
            Tranquility.AssetServiceResponse response = new Tranquility.AssetServiceResponse(result.response);
            OrderItem srcOi = (OrderItem) task.getContext('OrderItem');
            // Store OrderItem.Id -> Asset.Id
            Map<String,String> oiToAsset = (Map<String,String>) PWUtils.getSetFromMap(processData,'OrderItemToAsset', new Map<String,String>());
            oiToAsset.put(srcOi.Id, response.asset.Id);
            Map<String,String> assetToOi = (Map<String,String>) PWUtils.getSetFromMap(processData,'AssetToOrderItem', new Map<String,String>());
            assetToOi.put(response.asset.Id, srcOi.Id);
            if((Boolean) task.getContext('isNew')) {
                List<String> newAssetIds = (List<String>) PWUtils.getSetFromMap(processData,'NewAssetIds', new List<String>());
                newAssetIds.add(response.asset.Id);
                if(srcOi.SBQQ__RequiredBy__c != null) {
                    Map<String,String> oiToParent = (Map<String,String>) PWUtils.getSetFromMap(processData,'OrderItemToParent', new Map<String,String>());
                    oiToParent.put(srcOi.Id, srcOi.SBQQ__RequiredBy__c);
                }
            } else {
                List<String> updatedAssetIds = (List<String>) PWUtils.getSetFromMap(processData,'UpdatedAssetIds', new List<String>());
                updatedAssetIds.add(response.asset.Id);
            }
            List<Asset> touchedAssets = (List<Asset>)PWUtils.getSetFromMap(processData, 'TouchedAssets', new List<Asset>());
            switch on task.request.action {
                when 'generate' {
                    Tranquility.GenerateAssetRequest baseReq = (Tranquility.GenerateAssetRequest) JSON.deserialize(task.request.body, Tranquility.GenerateAssetRequest.class);
                    touchedAssets.add(
                        new Asset(
                            Id=response.asset.Id,
                            AccountId=baseReq.accountId,
                            Product2Id=baseReq.productId,
                            Name=baseReq.assetName
                        )
                    );
                }
                when 'change' {
                    Tranquility.ChangeAssetRequest baseReq = (Tranquility.ChangeAssetRequest) JSON.deserialize(task.request.body, Tranquility.ChangeAssetRequest.class);
                    touchedAssets.add(baseReq.getAsset(getAssetFields()));
                }
            }
        }
    }

    // private class PostUpdateAssets implements AssetManagementProcessTask.PostProcessingHook {
    //     public void process(AssetManagementProcessTask task, AssetManagementProcessTask.Result taskResult, Map<String,Object> processData) {
    //         List <Asset> touchedAssets = (List<Asset>) PWUtils.getSetFromMap(processData, 'TouchedAssets', new List<Asset>());
    //         if(task.type == AssetManagementProcessTask.TaskType.DML) {
    //             for (SObject obj : task.records) {
    //                 if(String.valueOf(obj.getSObjectType()) == 'Asset') {
    //                     findMatchingAsset.setComparisonAsset((Asset)obj);
    //                     Integer idx = PWUtils.findIndex(touchedAssets, findMatchingAsset);
    //                     if(idx == -1) {
    //                         touchedAssets.add((Asset)obj);
    //                     } else {
    //                         Asset existing = touchedAssets[idx];
    //                         touchedAssets.remove(idx);
    //                         touchedAssets.add((Asset) PWUtils.assign(existing, obj));
    //                     }
    //                 }
    //             }
    //         }
    //     }
    // }

    private class PostCancelAsset implements AssetManagementProcessTask.PostProcessingHook {
        public void process(AssetManagementProcessTask task, AssetManagementProcessTask.Result result, Map<String,Object> processData) {
            List<String> cancelledAssetIds = (List<String>) PWUtils.getSetFromMap(processData, 'CancelledAssetIds', new List<String>());
            Tranquility.AssetServiceResponse resp = new Tranquility.AssetServiceResponse(result.response);
            cancelledAssetIds.add(resp.asset.Id);
        }
    }

    private class PostInsertAggregateAsset implements AssetManagementProcessTask.PostProcessingHook {
        public List<Asset> toUpdate;
        public PostInsertAggregateAsset(List<Asset> toUpdate) {
            this.toUpdate = toUpdate;
        }
        /**
         * @description toUpdate should contains assets that were aggregated to the response asset as part of this task. 
         *                 Here, we retrieve the id for the created assets that match what is in toUpdate and then add the aggregate asset id
         * @param  task        task description
         * @param  result      result description
         * @param  processData processData description
         */ 
        public void process(AssetManagementProcessTask task, AssetManagementProcessTask.Result result, Map<String,Object> processData) {
            // System.assertEquals('generate', task.request.action);
            Tranquility.AssetServiceResponse response = new Tranquility.AssetServiceResponse(result.response);
            Tranquility.GenerateAssetRequest baseReq = (Tranquility.GenerateAssetRequest) JSON.deserialize(task.request.body, Tranquility.GenerateAssetRequest.class);
            System.debug('POST_INSERT_AGGREGATE_ASSET');
            System.debug('toUpdate:\n' + JSON.serialize(this.toUpdate));
            System.assertEquals(AssetManagementProcessTask.TaskType.CALLOUT,task.type);
            List<Asset> touchedAssets = (List<Asset>)PWUtils.getSetFromMap(processData, 'TouchedAssets', new List<Asset>());
            List<Asset> newAggregateAssets = (List<Asset>) PWUtils.getSetFromMap(processData,'NewAggregateAssets', new List<Asset>());
            Map<String,String> assetToAggAsset = (Map<String,String>) PWUtils.getSetFromMap(processData, 'AssetToAggregateAsset', new Map<String,String>());
            Map<String,List<String>> aggAssetToAssets = (Map<String,List<String>>) PWUtils.getSetFromMap(processData, 'AggregateAssetToAssets', new Map<String,List<String>>());
            Boolean first = true;
            if(touchedAssets != null) {
                for (Asset toUpdateAsset : this.toUpdate) {
                    findMatchingAsset.setComparisonAsset(toUpdateAsset);
                    Asset touchedAsset = (Asset) PWUtils.find(touchedAssets, findMatchingAsset);
                    if(touchedAsset == null || touchedAsset.Id == null) { // The aggregated record should be created and stored
                        throw new AssetManagementException('Aggregate asset Id cannot be found.');
                    } else {
                        assetToAggAsset.put(touchedAsset.Id, response.asset.Id);
                        List<String> childIds = (List<String>) PWUtils.getSetFromMap(aggAssetToAssets, response.asset.Id, new List<String>());
                        childIds.add(touchedAsset.Id);
                        toUpdateAsset.Aggregate_Asset__c = response.asset.Id;
                        toUpdateAsset.Id = touchedAsset.Id;
                    }
                }
            } else {
                throw new AssetManagementException('Error when preparing asset aggregation update: no asset data found.');
            }
            if(task.request.action == 'generate') {
                newAggregateAssets.add(
                    new Asset(
                        Id=response.asset.Id,
                        AccountId=baseReq.accountId,
                        Product2Id=baseReq.productId,
                        Name=baseReq.assetName
                    )
                );
            }
            if(!Test.isRunningTest()) {
                update toUpdate;
            }
        }
    }

    private class PreUpdateAggregateAssets implements AssetManagementProcessTask.PreProcessingHook {
        public void process(AssetManagementProcessTask task, Map<String,Object> processData) {
            Map<String,String> oiToAsset = (Map<String,String>) PWUtils.getSetFromMap(processData,'OrderItemToAsset', new Map<String,String>());
            Map<String,String> oiToParent = (Map<String,String>) PWUtils.getSetFromMap(processData,'OrderItemToParent', new Map<String,String>());
            Map<String,String> assetToOi = (Map<String,String>) PWUtils.getSetFromMap(processData,'AssetToOrderItem', new Map<String,String>());
            List<Asset> newAggregateAssets = (List<Asset>) PWUtils.getSetFromMap(processData,'NewAggregateAssets', new List<Asset>());
            Map<String,String> assetToAggAsset = (Map<String,String>) PWUtils.getSetFromMap(processData, 'AssetToAggregateAsset', new Map<String,String>());
            Map<String,List<String>> aggAssetToAssets = (Map<String,List<String>>) PWUtils.getSetFromMap(processData, 'AggregateAssetToAssets', new Map<String,List<String>>());
            for (Asset a : newAggregateAssets) {
                List<String> childIds = aggAssetToAssets.get(a.Id);
                System.assertNotEquals(null, childIds);
                System.assertNotEquals(0, childIds.size());
                String childAsset_oiId = assetToOi.get(childIds[0]);
                String childAsset_oi_parentId = oiToParent.get(childAsset_oiId);
                String childAsset_parentId = oiToAsset.get(childAsset_oi_parentId);
                String parentAssetId = assetToAggAsset.get(childAsset_parentId);
                task.records.add(
                    new Asset(
                        Id=a.Id,
                        ParentId=parentAssetId
                    )
                );
            }
        }
    }

    private class FindMatchingAsset implements PWUtils.FindFunction {
        Asset comparisonAsset;
        void setComparisonAsset(Asset a) {
            this.comparisonAsset = a;
        }
        public Boolean test (Object obj) {
            System.debug('OBJ:\n'+JSON.serialize(obj)+'\nCOMPARISON:\n'+JSON.serialize(this.comparisonAsset));
            return ((Asset)obj).AccountId == this.comparisonAsset.AccountId && ((Asset)obj).Product2Id == this.comparisonAsset.Product2Id;
        }
    }

    private class AggregateAssetInput {
        AssetAction assetAction;
        List<Id> sourceIds = new List<Id>();
        List<AssetStatePeriod> assetStatePeriods;
        String currencyIsoCode;
        public AggregateAssetInput(Tranquility.GenerateResult result) {
            this.assetAction = new AssetAction(
                Asset=result.asset,
                Amount=result.amount,
                MrrChange=result.mrrChange,
                QuantityChange=result.quantityChange,
                ActionDate=result.request.assetAction.actionDate,
                CategoryEnum=result.request.assetAction.category
            );
            if(result.request instanceof Tranquility.GenerateAssetRequest) {
                this.currencyIsoCode = ((Tranquility.GenerateAssetRequest)result.request).currencyIsoCode;
            } else {
                this.currencyIsoCode = ((Tranquility.UpsertAssetRequest) result.request).getAsset(getAssetFields()).CurrencyIsoCode;
            }
            this.sourceIds.add(result.oi.Id);
            this.assetStatePeriods = new List<AssetStatePeriod>{
                result.newPeriod.toAssetStatePeriod()
            };
        }
    }

    private class AssetItemsFilter implements PWUtils.FilterFunction {
        public Boolean filter(Object item) {
            return ((OrderItem) ((NestedObject)item).obj).Product2.AssetConversion__c != null;
        }
    }
}