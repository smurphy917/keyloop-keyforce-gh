public with sharing class UpsertAssets {
    
    private static List<String> orderItemFields() {
        return new List<String>{

        };
    }
    public static void upsert(Id orderId) {
        List<OrderItem> ois = PWUtils.selectStar(...);
        for (OrderItem oi : ois) {
            if(!isRootOrderItem(oi)) {
                continue;
            }
            String rootAssetId = getRootAssetId(oi);
            if(rootAssetId == null) {
                rootAssetId = 'TEMP:' + oi.Id;
            }
            rootAssetIds.add(rootAssetId);
        }
        for (String rootAssetId : rootAssetIds) {
            NestedObject bom;
            if(rootAssetId.startsWith('TEMP:')) {
                bom = getBOMForOrderItem(rootAssetId.split(':')[1], ois);
                rollUp(bom);
                createAssetsForBOM(bom);
            } else {
                bom = getBOMforAsset(rootAssetId);
                for (OrderItem oi : ois) {
                    if(getRootAssetId(oi) == rootAssetId) {
                        mergeOiToBOM(bom, oi);
                    }
                }
            }
            aggregate(bom);
        }
    }
    private Boolean isRootOrderItem(OrderItem oi) {
        return oi.Id == oi.SBQQ__BundleRoot__c;
    }
    private String getRootAssetId(OrderItem oi) {
        return oi.Modified_Root_Asset__c;
    }
    private NestedObject getBOMForOrderItem(Id rootOrderItemId, List<OrderItem> ois) {
        List<OrderItem> bomOis = new List<OrderItem>();
        for (OrderItem oi : ois) {
            if(oi.SBQQ__BundleRoot__c == rootOrderItemId) {
                bomOis.add(oi);
            }
        }
        return new NestedObject(
            bomOis,
            'Id',
            'SBQQ__RequiredBy__c'
        );
    }
    private void rollUp(NestedObject no) {

    }
    private void createAssetsForBOM(NestedObject bom) {
        for(NestedObject node : bom.all()) {
            node.relatedObjs.put('OrderItem', node.obj);
            node.replace(
                createAssetNode((OrderItem)node.obj)
            );
        }
    }
    private NestedObject getBOMForAsset(Id assetId, Datetime dt) {
        List<Asset> assets = PWUtils.selectStar(
            'Asset', 
            'RootAssetId = \'' + assetId + '\'',
            getAssetExpandFields()
        );
        return new NestedObject(
            assets,
            'Id',
            'ParentId'
        );
    }
    private void mergeOiToBOM(NestedObject bom, OrderItem oi) {
        if(oi.Asset__c != null) {
            // amendment to existing asset
            NestedObject match = bom.findById(oi.Asset__c);
            changeAsset(match, oi);
        } else {
            // new child of existing asset
            Id parentAssetId;
            if(oi.SBQQ__RequiredBy__c != null) {
                // Parent exists on the order
                parentAssetId = getOrderItemById(oi.SBQQ__RequiredBy__c).Asset__c;
            } else {
                // Parent not on the order
                parentAssetId = oi.SBQQ__QuoteLine__r.SBQQ__RequiredBy__r.SBQQ__UpgradedAsset__c;
            }
            NestedObject parentMatch = bom.findById(parentAssetId);
            parentMatch.addChild(
                createAssetNode(oi)
            );
        }
    }
    private NestedObject createAssetNode(OrderItem oi) {
        Asset a = new Asset(
            Name=oi.Product.Name,
            AccountId=oi.SBQQ__ShippingAccount__c
        );
        a.AssetStatePeriods.add(
            new AssetStatePeriod(
                StartDate=oi.ServiceDate,
                EndDate=oi.EndDate,
                Quantity=oi.Quantity,
                Mrr=mrr,
                Amount=oi.TotalPrice
            )
        );
        PWUtils.twinFields(oi, a, new String[]{'Name','AccountId'});
    }

}
