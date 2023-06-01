public with sharing class Thrill {

    public enum TransactionType {
        Amendment,
        Renewal,
        Revocation,
        Recontract
    }

    public static boolean disableCalculation = false;
    public static boolean autoClose = true;
    
    
    public static List<SBQQ__QuoteLine__c> GenerateQuoteLines(Id assetId, Date d, TransactionType type, List<Id> accountIds, Id quoteId) {
        return GenerateQuoteLines(assetId, Datetime.newInstanceGmt(d, Time.newInstance(0, 0, 0, 0)), type, accountIds, quoteId);
    }
    public static List<SBQQ__QuoteLine__c> GenerateQuoteLines(Id assetId, Datetime asOf, TransactionType type, List<Id> accountIds, Id quoteId) {
        return GenerateQuoteLines(
            assetId,
            asOf,
            type,
            null,
            accountIds,
            quoteId,
            null,
            null
        );
    }
    public static List<SBQQ__QuoteLine__c> GenerateQuoteLines(Id assetId, Datetime asOf, TransactionType type, Map<Id,Juventas.IncrementalRenewal> assetQuantityOverride, List<Id> accountIds, Id quoteId, Date startDate, Date endDate) {
        // Asset a = [SELECT Id, Name, AccountId, Account.Type, Account.RecordType.DeveloperName, LifecycleStartDate, LifecycleEndDate, RootAssetId, Aggregate_Asset__c, Aggregate_Asset__r.AccountId, Aggregate_Asset__r.Account.Type, Aggregate_Asset__r.Account.RecordType.DeveloperName, CurrencyIsoCode FROM Asset WHERE Id = :assetId];
        

        Integer count = 0;
        Long timestamp = Datetime.now().getTime();

        String fmtDtt = asOf.format('yyyy-MM-dd\'T\'HH:mm:ssZ');
        String fmtDt = asOf.format('yyyy-MM-dd');
        List<String> assetFields = new String[]{
            'Product2.Renewal_Term__c',
            'Product2.SBQQ__SubscriptionTerm__c',
            'Product2.SBQQ__ChargeType__c',
            'Product2.SBQQ__SubscriptionPricing__c',
            '(SELECT Quantity, Mrr, Amount FROM AssetStatePeriods WHERE StartDate <= ' + fmtDtt + ' AND (EndDate = null OR EndDate >= ' + fmtDtt + '))',
            'Account.Type',
            'Account.RecordType.DeveloperName',
            'Aggregate_Asset__r.AccountId', 
            'Aggregate_Asset__r.Account.Type', 
            'Aggregate_Asset__r.Account.RecordType.DeveloperName'
        };
        Asset a = ((List<Asset>) PWUtils.selectStar('Asset', 'Id = \'' + assetId + '\'', assetFields))[0];
        
        Id customerId = a.AccountId;
        String accRecordType = a.Account.RecordType.DeveloperName;
        String accType = a.Account.Type;
        String whereClause;
        Map<Id, List<Asset>> rootAssetMap = new Map<Id, List<Asset>>();
        // TODO: filter on active/non-cancelled assets
        if(a.Aggregate_Asset__c != null) {
            customerId = a.Aggregate_Asset__r.AccountId;
            accRecordType = a.Aggregate_Asset__r.Account.RecordType.DeveloperName;
            accType = a.Aggregate_Asset__r.Account.Type;
            whereClause = 'Id = \'' + a.RootAssetId + '\' OR RootAssetId = \'' + a.RootAssetId + '\'';
        } else if (type != TransactionType.Renewal && type != TransactionType.Recontract && accountIds != null) {
            whereClause = '(Aggregate_Asset__c = \'' + a.RootAssetId + '\' OR Aggregate_Asset__r.RootAssetId = \'' + a.RootAssetId + '\') AND AccountId IN (\'' + String.join(accountIds, ',') + '\')';
        }  else {
            if(assetQuantityOverride != null) {
                List<String> overrideAssetIds = new List<String>();
                for (Id overrideAssetId : assetQuantityOverride.keySet()) {
                    overrideAssetIds.add(overrideAssetId);
                }
                whereClause = 'Aggregate_Asset__c = \'' + a.RootAssetId + '\' OR (Aggregate_Asset__r.RootAssetId = \'' + a.RootAssetId + '\' AND Id IN (\'' + String.join(overrideAssetIds, '\',\'') + '\'))';
            } else {
                whereClause = 'Aggregate_Asset__c = \'' + a.RootAssetId + '\' OR Aggregate_Asset__r.RootAssetId = \'' + a.RootAssetId + '\'';
            }
        }
        // Account assetAccount = [SELECT Id, RecordType.DeveloperName FROM Account WHERE Id = :customerId LIMIT 1];        
        List<Asset> rootAssets = new List<Asset>();
        List<Asset> allAssets = PWUtils.selectStar('Asset', whereClause, assetFields);
        // TBC
        /*
        if(rootAssets.size() == 0 && a.Aggregate_Asset__c == null) {
            whereClause = 'Id = \'' + a.RootAssetId + '\'';
            rootAssets = PWUtils.selectStar('Asset', whereClause, assetFields);
        }
        */
        for (Asset assetRow : allAssets) {
            if(assetRow.ParentId == null) {
                rootAssets.add(assetRow);
            } else if(assetQuantityOverride == null || assetQuantityOverride.containsKey(assetRow.Id)){
                if(!rootAssetMap.containsKey(assetRow.RootAssetId)) {
                    rootAssetMap.put(assetRow.RootAssetId, new List<Asset>());
                }
                rootAssetMap.get(assetRow.RootAssetId).add(assetRow);
            }
        }
        List<SBQQ__QuoteLine__c> qls = new List<SBQQ__QuoteLine__c>();
        // Map<Id,Id> childToParent = new Map<Id,Id>();
        Map<Id,String> assetIdToIntId = new Map<Id, String>();
        Map<String,String> intIdToParentIntId = new Map<String,String>();
        Map<Id,Integer> assetIdToKey = new Map<Id,Integer>();
        Boolean assetExists = false;
        Integer lineKey;
        Integer qlNumber = 1;
        for (Asset rootAsset : rootAssets) {
            if(!rootAssetMap.containsKey(rootAsset.Id)) {
                continue;
            }
            lineKey = count++; // quote.nextKey++;
            if(rootAsset.AssetStatePeriods.size() == 0) {
                // throw new InvalidDateException('Modify date is not valid for the root asset. Please ensure modify date is within the lifecycle of the asset.');
                continue;
            }
            Double multiplier = 1.0;
            Boolean renewalFlag = false;
            Boolean existingFlag = true;
            if(type == TransactionType.Renewal) {
                Integer renewalTerm = Integer.valueOf(rootAsset.Product2.Renewal_Term__c);
                if(renewalTerm == null){
                    renewalTerm = 12;
                }
                if(startDate == null) {
                    startDate = rootAsset.LifecycleEndDate.addDays(1).dateGmt();
                }
                if(endDate == null) {
                    endDate = startDate.addMonths(renewalTerm).addDays(-1);
                }
                renewalFlag = true;
                existingFlag = false;
            } else if (type == TransactionType.Revocation) {
                startDate = rootAsset.LifecycleEndDate.dateGmt();
                endDate = startDate.addDays(1);
                multiplier = 0.0;
            } else if (type == TransactionType.Recontract) {
                renewalFlag = true;
                existingFlag = false;
                // LTC-1518
                endDate = startDate.addMonths(Integer.valueOf(rootAsset.Product2.SBQQ__SubscriptionTerm__c)).addDays(-1);
            }
            if(startDate == null) {
                startDate = asOf.dateGmt();
            }
            if(endDate == null) {
                endDate = rootAsset.LifecycleEndDate.dateGmt();
            }
            assetExists = true;
            SBQQ__QuoteLine__c rootQl = new SBQQ__QuoteLine__c(
                InternalId__c = timestamp + '|' + lineKey
            );
            PWUtils.twinFields(rootAsset, rootQl, new String[]{'Name', 'SBQQ__Discount__c'});
            rootQl.SBQQ__Product__c = rootAsset.Product2Id;
            rootQl.SBQQ__Quote__c = quoteId;
            rootQl.SBQQ__Quantity__c = multiplier * rootAsset.AssetStatePeriods[0].Quantity;
            rootQl.SBQQ__PriorQuantity__c = rootAsset.AssetStatePeriods[0].Quantity;
            rootQl.SBQQ__Existing__c = existingFlag;
            rootQl.SBQQ__StartDate__c = startDate;
            rootQl.SBQQ__EndDate__c = endDate;
            // rootQl.SBQQ__Incomplete__c = true; //triggers re-calculation
            rootQl.Account__c = customerId;
            rootQl.Site__c = rootAsset.AccountId;
            rootQl.SBQQ__DefaultSubscriptionTerm__c = rootAsset.Product2.SBQQ__SubscriptionTerm__c;
            rootQl.Asset__c = rootAsset.Id;
            rootQl.CurrencyIsoCode = rootAsset.CurrencyIsoCode;
            rootQl.Account_Record_Type__c = accRecordType;
            rootQl.Quote_Account_Type__c = accType;
            rootQl.Is_Recontract__c = type == TransactionType.Recontract;
            rootQl.SBQQ__OriginalQuoteLineId__c = rootAsset.Original_Quote_Line__c;
            rootQl.SBQQ__Number__c = qlNumber++;
            if(rootAsset.SBQQ__RegularPrice__c > 0) {
                rootQl.Asset_Price__c = PWUtils.prorate(rootAsset.AssetStatePeriods[0].Mrr, PWUtils.Period.MONTH, startDate, startDate.addMonths(Integer.valueOf(rootAsset.Product2.SBQQ__SubscriptionTerm__c)).addDays(-1), PWUtils.ProrationMethod.MONTHLY_DAILY) / rootAsset.AssetStatePeriods[0].Quantity;
            }
            if(renewalFlag) {
                rootQl.SBQQ__Renewal__c = true;
                rootQl.SBQQ__SubscriptionTerm__c = rootAsset.Product2.SBQQ__SubscriptionTerm__c;
            }
            assetIdToIntId.put(rootAsset.Id, rootQl.InternalId__c);
            
            // whereClause = 'RootassetId = \'' + rootAsset.Id + '\' AND Status != \'Cancelled\'';
            // List<Asset> assets = PWUtils.selectStar('Asset', whereClause, assetFields);
            List<Asset> assets = new List<Asset>{rootAsset};
            assets.addAll(rootAssetMap.get(rootAsset.Id));
            List<Id> prodIds = new List<Id>{rootAsset.Product2Id};
            
            for (Asset assetIter : assets) {
                prodIds.add(assetIter.Product2Id);
            }
            // TODO move out of loop
            List<Product2> prods = [SELECT Id, (SELECT Id FROM SBQQ__Features__r WHERE Is_Legacy__c = true), (SELECT Id FROM SBQQ__OptionalFor__r WHERE SBQQ__ConfiguredSKU__c IN :prodIds), (SELECT Id FROM PriceBookEntries WHERE Pricebook2Id = :PWUtils.standardPricebookId AND CurrencyIsoCode = :a.CurrencyIsoCode) FROM Product2 WHERE Id IN :prodIds];
            // List<PricebookEntry> pbes = [SELECT Id, Product2Id, (SELECT Id FROM Product2.SBQQ__Features__r) FROM PricebookEntry WHERE Pricebook2Id = :PWUtils.standardPricebookId AND Product2Id IN :prodIds AND CurrencyIsoCode = :a.CurrencyIsoCode];
            Map<Id,Id> prodIdToPbeId = new Map<Id,Id>();
            List<Id> legacyProdIds = new List<Id>();
            Id legacyFeatureId;
            for (Product2 prod : prods) {
                prodIdToPbeId.put(prod.Id, prod.PricebookEntries[0].Id);
                if(prod.Id == rootAsset.Product2Id && prod.SBQQ__Features__r.size() > 0) {
                    legacyFeatureId = prod.SBQQ__Features__r[0].Id;
                }
                if(prod.SBQQ__OptionalFor__r.size() == 0) {
                    // No options for this item, should use legacy id
                    legacyProdIds.add(prod.Id);
                }
            }
            rootQl.SBQQ__PricebookEntryId__c = prodIdToPbeId.get(rootAsset.Product2Id);
            qls.add(rootQl);
            NestedObject assetBOM;
            try {
                assetBOM = new NestedObject(assets, 'Id', 'ParentId');
            } catch (NestedObject.NestedObjectException e) {
                System.assert(false);
            }
            for (NestedObject node : assetBOM.all()) {
                lineKey = count++; // quote.nextKey++;
                Asset asset = (Asset) ((NestedObject.NestableSObject) node.obj).obj;
                Asset parentAsset;
                if(node.parentId != null) {
                    parentAsset = (Asset) ((NestedObject.NestableSObject)  assetBOM.findById(node.parentId).obj).obj;
                }
                Id renewedAsset = null;
                if(asset.Id == rootAsset.Id) {
                    continue;
                }
                if(asset.AssetStatePeriods.size() == 0) {
                    continue;
                }
                AssetStatePeriod asp = asset.AssetStatePeriods[0]; // should only be one per query
                Boolean lineExistingFlag = existingFlag;
                // LTC-2826
                // if(asset.Product2.SBQQ__ChargeType__c == 'One-Time') {
                //     lineExistingFlag = true;
                // }
                if(asset.Product2.SBQQ__ChargeType__c == 'One-Time' && (type == TransactionType.Renewal || type == TransactionType.Recontract)) {
                    renewedAsset = asset.Id;
                }

                SBQQ__QuoteLine__c ql = new SBQQ__QuoteLine__c(
                    InternalId__c = timestamp + '|' + lineKey
                );

                Decimal lineQty = asp.Quantity;
                Decimal linePriorQty = asp.Quantity;
                Decimal unitMrr = 0;
                if(asp.Quantity != 0) {
                    unitMrr = asp.Mrr / asp.Quantity;
                }
                if(assetQuantityOverride != null) {
                    Juventas.IncrementalRenewal incr = assetQuantityOverride.get(asset.Id);
                    if(incr == null) {
                        System.debug('ASSET: ' + JSON.serialize(asset));
                        System.debug('ROOT ASSET MAP: ' + JSON.serialize(rootAssetMap));
                        System.debug('QTY OVERRIDES: ' + JSON.serialize(assetQuantityOverride));
                        System.assert(false);
                    }
                    lineQty = incr.targetQuantity;
                    if(lineQty == null) {
                        lineQty = incr.deltaQuantity;
                    }
                    linePriorQty = incr.priorQuantity;
                    if(incr.unitMrr != null) {
                        unitMrr = incr.unitMrr;
                    }
                }

                PWUtils.twinFields(asset, ql, new String[]{'Name', 'SBQQ__Discount__c'});
                ql.SBQQ__Product__c = asset.Product2Id;
                ql.SBQQ__Quote__c = quoteId;
                ql.SBQQ__PriorQuantity__c = linePriorQty;
                ql.SBQQ__Quantity__c = multiplier * lineQty;
                // LTC-4242 - use parent asset qty if node has a parent asset
                if(parentAsset != null && parentAsset.AssetStatePeriods.size() > 0) {
                    ql.SBQQ__BundledQuantity__c = lineQty / parentAsset.AssetStatePeriods[0].Quantity; 
                } else {
                    ql.SBQQ__BundledQuantity__c = lineQty / rootQl.SBQQ__PriorQuantity__c; 
                }
                ql.SBQQ__Existing__c = lineExistingFlag;
                ql.SBQQ__StartDate__c = startDate;
                ql.SBQQ__EndDate__c = endDate;
                ql.SBQQ__OptionType__c = 'Component';
                // ql.SBQQ__Incomplete__c = true; // triggers re-calculation
                ql.SBQQ__AllowAssetRefund__c = true;
                ql.Account__c = customerId;
                ql.Site__c = asset.AccountId;
                ql.SBQQ__PricebookEntryId__c = prodIdToPbeId.get(asset.Product2Id);
                ql.SBQQ__DefaultSubscriptionTerm__c = asset.Product2.SBQQ__SubscriptionTerm__c;
                ql.SBQQ__SubscriptionPricing__c = asset.Product2.SBQQ__SubscriptionPricing__c;
                ql.Asset__c = asset.Id;
                ql.SBQQ__Renewal__c = renewalFlag;
                ql.CurrencyIsoCode = asset.CurrencyIsoCode;
                ql.Account_Record_Type__c = accRecordType;
                ql.Quote_Account_Type__c = accType;
                ql.SBQQ__RenewedAsset__c = renewedAsset;
                ql.SBQQ__OriginalQuoteLineId__c = asset.Original_Quote_Line__c;
                ql.SBQQ__Number__c = qlNumber++;
                Decimal termDec = asset.Product2.SBQQ__SubscriptionTerm__c;
                if(termDec == null) {
                    termDec = rootAsset.Product2.SBQQ__SubscriptionTerm__c;
                    if(termDec == null) {
                        termDec = 12;
                    }
                }
                Integer term = Integer.valueOf(termDec);
                if(asset.Product2.SBQQ__ChargeType__c == 'One-Time') {
                    ql.Asset_Price__c = asset.SBQQ__RegularPrice__c;
                } else if(unitMrr > 0 && lineQty != 0) {
                    ql.Asset_Price__c = PWUtils.prorate(lineQty * unitMrr, PWUtils.Period.MONTH, startDate, startDate.addMonths(term).addDays(-1), PWUtils.ProrationMethod.MONTHLY_DAILY) / lineQty;
                } else {
                    ql.Asset_Price__c = PWUtils.prorate(lineQty * unitMrr, PWUtils.Period.MONTH, startDate, startDate.addMonths(term).addDays(-1), PWUtils.ProrationMethod.MONTHLY_DAILY);
                }
                if(legacyProdIds.contains(asset.Product2Id)) {
                    ql.SBQQ__DynamicOptionId__c = legacyFeatureId + ':' + asset.Product2Id;
                    ql.SBQQ__ProductOption__c = null;
                }
                
                assetIdToIntId.put(asset.Id, ql.InternalId__c);
                intIdToParentIntId.put(ql.InternalId__c, assetIdToIntId.get(asset.ParentId));
                qls.add(ql);
            }
        }
        if(!assetExists) {
            throw new InvalidDateException('Modify date [' + asOf + '] is not valid for the root asset. Please ensure modify date is within the lifecycle of the asset.');
        }
        if(Test.isRunningTest()) {
            update new List<SObject>{
                new SBQQ__Quote__c(
                    Id = quoteId,
                    SBQQ__Pricebook__c = PWUtils.standardPricebookId,
                    SBQQ__PricebookId__c = PWUtils.standardPricebookId
                ),
                new Opportunity(
                    Id = [SELECT SBQQ__Opportunity2__c FROM SBQQ__Quote__c WHERE Id = :quoteId].SBQQ__Opportunity2__c,
                    Pricebook2Id = PWUtils.standardPricebookId
                )
            }; 
        }
        SBQQ.TriggerControl.disable();
        insert qls;
        
        List<SBQQ__QuoteLine__c> toUpdateQls = new List<SBQQ__QuoteLine__c>();
        for (SBQQ__QuoteLine__c ql : qls) {
            String parentIntId = intIdToParentIntId.get(ql.InternalId__c);
            if(parentIntId != null) {
                toUpdateQls.add(
                    new SBQQ__QuoteLine__c(
                        Id = ql.Id,
                        SBQQ__RequiredBy__r = new SBQQ__QuoteLine__c(
                            InternalId__c = parentIntId
                        )
                    )
                );
            }
        }
        if(!disableCalculation) {
            SBQQ.TriggerControl.enable();
        }
        System.debug('INSERTED: ' + JSON.serialize(qls));
        System.debug('UPDATING: ' + JSON.serialize(toUpdateQls));
        update toUpdateQls;
        return null;
    }

    public static Id GenerateAndSave(Id assetId, Datetime dt, TransactionType type, List<Id> accountIds, Id oppOrQuoteId, String oppSubType) {
        return GenerateAndSave(
            assetId, //assetId
            null, // assetQuantityMap
            dt, // asOf
            null, // startDate
            null, // endDate
            type, // type
            accountIds, // accountIds
            oppOrQuoteId, // oppOrQuoteId
            oppSubType // oppSubType
        );
    }

    public static Id GenerateAndSave(Id assetId, Map<Id,Juventas.IncrementalRenewal> assetQuantityMap, Datetime asOf, Date startDate, Date endDate, TransactionType type, List<Id> accountIds, Id oppOrQuoteId, String oppSubType) {
        SavePoint sp = Database.setSavePoint();
        if(disableCalculation) {
            SBQQ.TriggerControl.disable();
        }
        try {
            Id oppId;
            Id quoteId;
            
            if(oppOrQuoteId != null) {
                if(oppOrQuoteId.getSobjectType().getDescribe().getName() == 'Opportunity') {
                    oppId = oppOrQuoteId;
                } else if(oppOrQuoteId.getSobjectType().getDescribe().getName() == 'SBQQ__Quote__c') {
                    quoteId = oppOrQuoteId;
                }
            }
            Asset a;
            Id customerId;
            if(assetId != null) {
                a = [SELECT Id, AccountId, Name, LifecycleEndDate, Aggregate_Asset__c, Aggregate_Asset__r.AccountId, CurrencyIsoCode FROM Asset WHERE ID = :assetId];
                customerId = a.AccountId;
                if(a.Aggregate_Asset__c != null) {
                    customerId = a.Aggregate_Asset__r.AccountId;
                }
            }
            Boolean quoteAutoClose = autoClose && type == TransactionType.Renewal;
            if(oppSubType == null){
                oppSubType = type.name();
            }
            String quoteType = type.name();
            String prefix = type.name();
            switch on type {
                when Renewal {
                    if(asOf == null) {
                        asOf = Datetime.newInstanceGmt(a.LifecycleEndDate.dateGmt(),Time.newInstance(0, 0, 0, 0));
                    }
                    if(startDate == null) {
                        startDate =a.LifecycleEndDate.dateGmt().addDays(1);
                    }
                    quoteId = ClearExistingRenewal(assetId, startDate);
                }
                when Revocation {
                    System.assert(a != null);
                    oppSubType = 'Free Trial'; // 'Amendment';
                    quoteType = 'Amendment';
                    prefix = 'Trial End';
                    quoteAutoClose = autoClose;
                    if(asOf == null) {
                        startDate = a.LifecycleEndDate.dateGmt();
                        asOf = startDate;
                    }
                }
                when Recontract {
                    System.assert(a != null);
                    quoteType = 'Renewal';
                    prefix = 'Re-contract';
                    quoteAutoClose = false;
                }
            }
            if(startDate == null) {
                startDate = asOf.dateGmt();
            }
            if(quoteId == null) {
                if(oppId == null) {
                    Opportunity opp = new Opportunity(
                        Name = prefix + ': ' + a.Name,
                        AccountId = customerId,
                        StageName = 'Qualification',
                        CloseDate = startDate,
                        Pricebook2Id = PWUtils.standardPricebookId,
                        CurrencyIsoCode = a.CurrencyIsoCode,
                        Type = 'Existing Business',
                        Sub_Type__c = oppSubType
                    );
                    insert opp;
                    // System.debug('OPP PB ID: ' + opp.Pricebook2Id);
                    oppId = opp.Id;
                }
                SBQQ__Quote__c q = new SBQQ__Quote__c (
                    SBQQ__Opportunity2__c = oppId,
                    SBQQ__Type__c = quoteType,
                    SBQQ__Primary__c = true,
                    SBQQ__Account__c = customerId,
                    SBQQ__PricebookId__c = PWUtils.standardPricebookId,
                    SBQQ__Pricebook__c = PWUtils.standardPricebookId,
                    SBQQ__StartDate__c = startDate,
                    Auto_Close__c = quoteAutoClose,
                    CurrencyIsoCode = a.CurrencyIsoCode
                );
                insert q;
                // System.debug('QUOTE PB IDs: ' + q.SBQQ__Pricebook__c + '/' + q.SBQQ__PricebookId__c);
                quoteId = q.Id;
                // System.debug('QUOTE ID: ' + q.Id);
            } else {
                SBQQ__Quote__c q = new SBQQ__Quote__c(
                    Id = quoteId,
                    SBQQ__Type__c = quoteType,
                    SBQQ__Primary__c = true,
                    SBQQ__StartDate__c = startDate
                );
                update q;
            }
            List<SBQQ__QuoteLine__c> qls = GenerateQuoteLines(assetId, asOf, type, assetQuantityMap, accountIds, quoteId, startDate, endDate);
            if(disableCalculation) {
                // Re-enable now, after all updates complete. Another update will be required (outside this method call) to trigger calculation
                SBQQ.TriggerControl.enable();
            }
            return quoteId;
        } catch (Exception e) {
            Database.rollback(sp);
            AssetManagementLog.logError(e, assetId, 'Create ' + type.name());
            return null;
        }
    }

    public static Id ClearExistingRenewal(Id assetId, Date renewalDate) {
        List<SBQQ__QuoteLine__c> qls = [
            SELECT Id, SBQQ__Quote__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__RenewedAsset__r.Aggregate_Asset__r.RootAssetId = :assetId AND 
                SBQQ__Quote__r.SBQQ__Type__c = 'Renewal' AND 
                SBQQ__StartDate__c = :renewalDate AND
                SBQQ__Quote__r.SBQQ__Status__c != 'Closed'
        ];
        if(qls.size() == 0) {
            return null;
        }
        Id quoteId = qls[0].SBQQ__Quote__c;
        delete qls;
        return quoteId;
    }

    public class InvalidDateException extends Exception {}
    public class ThrillingException extends Exception {}
}