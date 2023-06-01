@RestResource(urlmapping='/configurationBOM/v3/*')
global with sharing class ConfigurationBOMController {

  public static final String BOM_TYPE_ALL_SALES_LINES = 'BOM_TYPE_ALL_SALES_LINES';
  public static final String BOM_TYPE_ORDER_LINES_ONLY = 'BOM_TYPE_ORDER_LINES_ONLY';
  
  /*
  @HttpGet
  global static List<NestedObject.SanitisedNestedObject> handleGet() {
    RestRequest req = RestContext.request;
    String[] path = req.requestURI.substring(req.requestURI.indexOf('/') + 1).split('/');
    String obj = path[path.indexOf('v2') + 1];
    String id = path[path.indexOf('v2') + 2];
    List<String> fields = new List<String>();
    Boolean salesOnly = false;
    if(req.params.containsKey('fields')) {
      String[] rawFields = req.params.get('fields').split(',');
      for (String rawField : rawFields) {
        fields.add(rawField.trim());
      }
    }
    if(req.params.containsKey('salesOnly')) {
      salesOnly = req.params.get('salesOnly').trim().toLowerCase() == 'true';
    }
    List<NestedObject> rawResult;
    switch on obj {
      when 'order', 'Order' {
        Order o = new Order(Id=id);
        rawResult = getBOMsForOrder(o, fields, salesOnly);
      }
      when 'quote', 'Quote', 'SBQQ__Quote__c' {
        SBQQ__Quote__c q = new SBQQ__Quote__c(Id=id);
        rawResult = getBOMsForQuote(q, fields, salesOnly);
      }
      when 'orderLine', 'OrderItem', 'OrderLine', 'OrderProduct' {
        OrderItem oi = [SELECT OrderId FROM OrderItem WHERE Id = :id];
        rawResult = new List<NestedObject>{getBOMForOrderItem(oi, fields, salesOnly)};
      }
      when 'quoteLine', 'QuoteLine', 'SBQQ__QuoteLine__c' {
        SBQQ__QuoteLine__c ql = [SELECT SBQQ__Quote__c FROM SBQQ__QuoteLine__c WHERE Id = :id];
        rawResult = new List<NestedObject>{getBOMForQuoteLine(ql, fields, salesOnly)};
      }
      when else {
        rawResult = new List<NestedObject>();
      }
    }
    List<NestedObject.SanitisedNestedObject> result = new List<NestedObject.SanitisedNestedObject>();
    for (NestedObject no : rawResult) {
      result.add(no.sanitise());
    }
    return result;
  }

  @HttpPost
  global static List<NestedObject.SanitisedNestedObject> consumePost() {
    IncomingPayload req = (IncomingPayload) JSON.deserialize(RestContext.request.requestBody.toString(), IncomingPayload.class);
    List<NestedObject> fullBoms;
    Boolean salesOnly = false;
    if(req.salesOnly != null) {
      salesOnly = req.salesOnly;
    }
    if(req.order != null) {
      fullBoms = getBOMsForOrder(req.order, req.fields, salesOnly);
    } else if(req.quote != null) {
      fullBoms = getBOMsForQuote(req.quote, req.fields, salesOnly);
    } else if(req.quoteLine != null) {
      fullBoms = new List<NestedObject>{getBOMForQuoteLine(req.quoteLine, req.fields, salesOnly)};
    } else if(req.orderItem != null) {
      fullBoms = new List<NestedObject>{getBOMForOrderItem(req.orderItem, req.fields, salesOnly)};
    }
    if(fullBoms != null) {
      List<NestedObject.SanitisedNestedObject> result = new List<NestedObject.SanitisedNestedObject>();
      for (NestedObject bom : fullBoms) {
        result.add(bom.sanitise());
      }
      return result;
    }
    return new List<NestedObject.SanitisedNestedObject>();
  }

  private class IncomingPayload {
    Order order;
    SBQQ__Quote__c quote;
    SBQQ__QuoteLine__c quoteLine;
    OrderItem orderItem;
    List<String> fields;
    Boolean salesOnly;
  }
  */
  /*
  @AuraEnabled(cacheable=true)
  public static List<NestedObject> getBOMsForOrder(
    Order order,
    List<String> fields,
    Boolean salesOnly
  ) {
    Set<String> queryFields = new Set<String>{
      'Id',
      'SBQQ__BundleRoot__c',
      'SBQQ__RequiredBy__c',
      'Product2Id',
      'Product2.Name'
    };
    if(OrgSettings.LogikEnabled) {
      queryFields.add('SBQQ__QuoteLine__r.LGK__Logik_Id__c');
    }
    String configIdField = null;
    if(OrgSettings.LogikEnabled) {
      configIdField = 'SBQQ__QuoteLine__r.LGK__Logik_Id__c'; // configIdField
    }
    queryFields.addAll(fields);
    List<NestedObject> fullBoms = getBOMsForObject(
      order.Id, // parentId
      OrderItem.class, // childType
      'OrderId',// childToParentIdField
      'SBQQ__BundleRoot__c', // bundleIdField
      configIdField,
      'SBQQ__RequiredBy__c',
      'Product2Id', // prodIdField
      new List<String>(queryFields) // queryFields
    );
    if(salesOnly) {
      return removeCfgOnlyNodes(fullBoms);
    }
    return fullBoms;
  }
  */

  public static List<NestedObject> getBOMsForOrder(
    Order order,
    List<String> fields,
    String bomType
  ) {
    Set<String> queryFields = new Set<String>{
      'Id',
      'Modified_Root_Asset__c',
      'SBQQ__RequiredBy__c',
      'Product2Id',
      'Product2.Name',
      'Modified_Root_Asset__c'
    };
    // if(OrgSettings.LogikEnabled) {
    //   queryFields.add('SBQQ__QuoteLine__r.LGK__Logik_Id__c');
    // }
    queryFields.addAll(fields);
    String configIdField = null;
    // if(OrgSettings.LogikEnabled) {
    //   configIdField = 'SBQQ__QuoteLine__r.LGK__Logik_Id__c';
    // }
    List<NestedObject> fullBoms = getBOMsForObject(
      order.Id, // parentId
      OrderItem.class, // childType
      'OrderId',// childToParentIdField
      'SBQQ__BundleRoot__c', // bundleIdField
      configIdField,
      'SBQQ__RequiredBy__c',
      'Product2Id', // prodIdField
      new List<String>(queryFields) // queryFields
    );
    // System.debug('FULL BOMS:\n' + JSON.serialize(fullBoms));
    if(bomType == BOM_TYPE_ORDER_LINES_ONLY) {
      return removeCfgOnlyNodes(fullBoms);
    } else if(bomType == BOM_TYPE_ALL_SALES_LINES) {
      return removeMfgNodes(fullBoms);
    }
    return null;
    /*
    List<NestedObject> finalBoms;
    List<NestedObject> mergedBoms;
    Map<Id,NestedObject> assetIdToBom = new Map<Id,NestedObject>();
    for (NestedObject rootBom : fullBoms) {
      OrderItem oi = (OrderItem) rootBom.obj;
      if(oi.Modified_Root_Asset__c != null) {
        NestedObject base;
        Boolean stored = false;
        if(assetIdToBom.containsKey(oi.Modified_Root_Asset__c)) {
          stored = true;
          base = assetIdToBom.get(oi.Modified_Root_Asset__c);
        } else {
          base = getBOMForAsset(((orderItem)rootBom.obj).Modified_Root_Asset__r, oi.ServiceDate, AssetManagement.getAssetFields(), true);
        }
        NestedObject merged = NestedObject.assign(
          base,
          rootBom,
          'Product2Id',
          'Product2Id',
          'Asset__r.Parent.Product2Id',
          null,
          assignFunc
        );
        assetIdToBom.put(oi.Modified_Root_Asset__c, merged);
        if(!stored) {
          mergedBoms.add(merged);
        }
      } else {
        finalBoms.add(rootBom);
      }
    }
    for (NestedObject mergedBom : mergedBoms) {
      finalBoms.addAll(mergedBom.filter(new FilterOnlyMappedLines()));
    }
    return finalBoms;
    */
  }

  public static NestedObject getBOMForAsset(
    Id assetId,
    Datetime asOf,
    List<String> fields,
    Boolean salesOnly
  ) {
    String query = String.format('SELECT {0} FROM Asset WHERE Id = \'\'{1}\'\'', new List<String>{
      String.join(fields,','),
      assetId
    });
    System.debug(query);
    return getBOMForAsset(
      (Asset) Database.query(query),
      asOf,
      fields,
      salesOnly
    );
  }

  @AuraEnabled(cacheable=true)
  public static NestedObject getBOMForAsset(
    Asset asset,
    Datetime asOf,
    List<String> fields,
    Boolean salesOnly
  ) {
    /**
     * 1. Find root asset
     * 2. Retrieve LGK id
     * 3. Get BOM for LGK id
     * 4. 
     */

    String configId = AssetManagement.getAssetConfigId(asset.RootAssetId, asOf);
    if (configId == null) {
      // TODO: throw error
    }

    
    Set<String> queryFields = new Set<String>{
      'Id',
      'Product2Id',
      'RootAssetId',
      'ParentId'
    };
    queryFields.addAll(fields);
    String configIdField;
    if(!OrgSettings.LogikEnabled) {
      configIdField = 'ParentId';
    }
    NestedObject bom = getBOMForObject(
      asset.RootAssetId, // parentId
      Asset.class, // childType
      'RootAssetId', // childToParentIdField
      configIdField, // configIdField
      configId, // configId
      'Product2Id', //productIdField
      new List<String>(queryFields) // queryFields
    );
    return removeMfgNodes(new List<NestedObject>(new NestedObject[]{bom})).get(0);
  }
  /*
  @AuraEnabled(cacheable=true)
  public static List<NestedObject> getBOMsForQuote(
    SBQQ__Quote__c quote,
    List<String> fields,
    Boolean salesOnly
  ) {
    Set<String> queryFields = new Set<String>{
      'Id',
      // 'LGK__Logik_Id__c',
      'SBQQ__RequiredBy__c',
      'SBQQ__Product__c',
      'SBQQ__Product__r.Name',
      'SBQQ__RequiredBy__c'
    };
    if(OrgSettings.LogikEnabled) {
      queryFields.add('LGK__Logik_Id__c');
    }
    queryFields.addAll(fields);
    String configIdField = null;
    if(OrgSettings.LogikEnabled) {
      configIdField = 'LGK__Logik_Id__c';
    }
    List<NestedObject> fullBoms = getBOMsForObject(
      quote.Id, // parentId
      SBQQ__QuoteLine__c.class, // childType
      'SBQQ__Quote__c',// childToParentIdField
      'SBQQ__BundleRoot__c', // bundleIdField
      configIdField,
      'SBQQ__RequriredBy__c',
      'SBQQ__Product__c', // prodIdField
      new List<String>(queryFields) // queryFields
    );
    if(salesOnly) {
      return removeCfgOnlyNodes(fullBoms);
    }
    return fullBoms;
  }
  */

  private static List<NestedObject> getBOMsForObject(
    ID parentId,
    Type childType,
    String childToParentIdField,
    String bundleIdField, // defines the full bundle, only on the children
    String configIdField, // defines the full bundle, only on the root
    String parentIdField, // hierarchical relationship within bundle
    String prodIdField,
    List<String> queryFields
  ) {
    String query = String.format('SELECT {0} FROM {1} WHERE {2}', new List<String>{String.join(queryFields, ','), childType.getName(), childToParentIdField + ' = \'' + parentId + '\''});
    List<NestedObject> boms = new List<NestedObject>();
    List<SObject> lines = Database.query(query);
    List<String> cfgIds = new List<String>();
    List<String> bundleIds = new List<String>();
    List<Id> bundleChildren = new List<Id>();
    Map<ID, SObject> rootLines = new Map<ID, SObject>();
    Map<String, SObject> cfgProdToLine = new Map<String, SObject>();
    for (SObject l : lines) {
      ID bundleId = (ID) l.get(bundleIdField);
      ID prodId = (ID) l.get(prodIdField);
      String configId;
      if(configIdField != null) {
        configId = (String) PWUtils.getField(l, configIdField);
      }
      if(configId != null) {
        cfgProdToLine.put(configId + '|' + prodId, l);
        if( !cfgIds.contains(configId)) {
          cfgIds.add(configId);
        }
      } else if(bundleId != null) {
        //check if parent item has a config id and use that instead
        SObject parent = rootLines.get(bundleId);
        String parentConfigId;
        if(configIdField != null) {
          parentConfigId = (String) PWUtils.getField(parent, configIdField);
        }
        if(parentConfigId != null) {
          cfgProdToLine.put(parentConfigId + '|' + prodId, l);
        } else {
          // No config id, so use standard bundle relationship
          if(!bundleIds.contains(bundleId)) {
           bundleIds.add(bundleId);
          }
          bundleChildren.add(l.Id);
        }
      }
      if(bundleId == null) {
        rootLines.put(l.Id, l);
        if(!cfgProdToLine.containsKey(configId + '|ROOT')) {
          cfgProdToLine.put(configId + '|ROOT', l);
        } else {
          cfgProdToLine.put(configId + '|ROOT', null); // this way it doesn't get reset on a 3rd item.
        }
      }
    }
    // for (String configId : cfgIds) {
    //   NestedObject bom = getBOMForId(configId);
    //   for (NestedObject cfg : bom.all()) {
    //     if(cfg.obj == null || cfg.obj.getSObjectType().getDescribe().getName() == childType.getName()){
    //       continue;
    //     }
    //     String mapKey = configId + '|';
    //     // if(OrgSettings.LogikEnabled) {
    //     //   mapKey += (String) PWUtils.getField(cfg.obj, prodIdField);
    //     // } 
    //     // else {
    //     //   throw new ConfigurationBOMException('Config ID is not supported when the org is not Logik enabled.');
    //     // }
    //     SObject l = cfgProdToLine.get(mapKey);
    //     if(l != null) {
    //       cfg.replaceObject(l);
    //       cfgProdToLine.remove(mapKey);
    //     }
    //   }
    //   SObject root = cfgProdToLine.get(configId + '|ROOT');
    //   if(root != null && bom.obj == null) {
    //     bom.replaceObject(root);
    //   } else if (root != null) {
    //     if(cfgProdToLine.containsKey(configId + '|' + PWUtils.getField(root, prodIdField))) {
    //       // root item was never added to BOM. Add it as a new level in the BOM.
    //       NestedObject rootBom = new NestedObject(root);
    //       rootBom.addChild(bom);
    //       bom = rootBom;
    //     }
    //   }
    //   boms.add(bom);
    // }
    // bundleIds = new List<String>();
    for(Id childId : bundleChildren) {
      Integer bundleIdsIdx = bundleIds.indexOf(childId);
      if(bundleIdsIdx > -1) {
        // Since this item has a bundleId, remove it from the bundleIds;
        bundleIds.remove(bundleIdsIdx);
      }
    }
    for (Id rootId : rootLines.keySet()) {
      if(!bundleIds.contains(rootId)) {
        bundleIds.add(rootId);
      }
    }
    
    // System.debug('BUNDLE_IDs:' + JSON.serialize(bundleIds));
    for (String bundleId : bundleIds) {
      String bundleQuery = String.format('SELECT {0} FROM {1} WHERE {2}', new List<String>{String.join(queryFields, ','), childType.getName(), childToParentIdField + ' = \'' + parentId + '\' AND (Id = \'' + bundleId + '\' OR ' + bundleIdField + ' = \'' + bundleId + '\')'});
      NestedObject bom = new NestedObject(
        Database.query(bundleQuery),
        'Id',
        parentIdField);
      boms.add(bom);
    }
    return boms;
  }

  private static NestedObject getBOMForObject(
    ID parentId,
    Type childType,
    String childToParentIdField,
    String configIdField,
    String configId,
    String prodIdField,
    List<String> queryFields
  ) {
    String query = String.format('SELECT {0} FROM {1} WHERE {2}', new List<String>{String.join(queryFields, ','), childType.getName(), childToParentIdField + ' = \'' + parentId + '\''});
    List<SObject> lines = Database.query(query);
    if(OrgSettings.LogikEnabled) {
      // Map<ID, SObject> prodToLine = new Map<ID, SObject>();
      // for (SObject l : lines) {
      //   ID prodId = (ID) l.get(prodIdField);
      //   prodToLine.put(prodId, l);
      //   if(configId == null && configIdField != null) {
      //     configId = (String) PWUtils.getField(l, configIdField);
      //   }
      // }
      // NestedObject bom = getBOMForId(configId);
      // for(NestedObject cfg : bom.all()) {
      //   if(cfg.obj == null || cfg.obj.getSObjectType().getDescribe().getName() == childType.getName()){
      //     // node is a <childType> record (this isn't likely as getBOMForId returns LGK__ConfigurationBOM__c nodes)
      //     continue;
      //   }
      //   // node is a LGK__ConfigurationBOM__c record
      //   String mapKey = (String) PWUtils.getField(cfg.obj, 'Product__c');
      //   SObject l = prodToLine.get(mapKey);
      //   if(l != null) {
      //     cfg.replaceObject(l);
      //     prodToLine.remove(mapKey);
      //   }
      // }
      // return bom;
      return null;
    } else {
      return new NestedObject(
        lines,
        'Id',
        configIdField
      );
    }
  }
  /*
  @AuraEnabled(cacheable=true)
  public static NestedObject getBOMForQuoteLine (
    SBQQ__QuoteLine__c quoteLine,
    List<String> fields,
    Boolean salesOnly
  ){
    List<NestedObject> quoteBoms = getBOMsForQuote(new SBQQ__Quote__c(Id=quoteLine.SBQQ__Quote__c), fields, salesOnly);
    for (NestedObject bom : quoteBoms) {
      NestedObject node = bom.findById(quoteLine.Id);
      if(node != null) {
        return node;
      }
    }
    return null;
  }
  */
  /*
  @AuraEnabled(cacheable=true)
  public static NestedObject getBOMForOrderItem (
    OrderItem orderItem,
    List<String> fields,
    Boolean salesOnly
  ) {
    List<NestedObject> orderBoms = getBOMsForOrder(new Order(Id=orderItem.OrderId), fields, salesOnly);
    for (NestedObject bom : orderBoms) {
      NestedObject node = bom.findById(orderItem.Id);
      if(node != null) {
        return node;
      }
    }
    return null;
  }
  */

  // public static NestedObject getBOMForId (String configId) {
  //   // if(!OrgSettings.LogikEnabled) {
  //   //   throw new ConfigurationBOMException('Cannot retrieve BOM for configuration Id when org is not Logik enabled.');
  //   // }
  //   if(OrgSettings.LogikEnabled) {
  //     // return new NestedObject(
  //     //   PWUtils.selectStar('LGK__ConfigurationBOM__c', 'LGK__Configuration_Id__c = \'' + configId + '\'', new List<String>{'Product__r.Name', 'Parent__r.Product__r.Name', 'Parent__r.Product__c'} ),
  //     //   'LGK__Unique_Id__c',
  //     //   'LGK__Parent_Product_Id__c'
  //     // );
  //     return null;
  //   } else {
  //     return new NestedObject(
  //       PWUtils.selectStar('Asset', 'RootAssetId = \'' + configId + '\'', new List<String>{'Product2.Name', 'Parent.Product2.Name','Parent.Product2Id'} ),
  //       'Id',
  //       'ParentId'
  //     );
  //   }
  // }

  public static List<NestedObject> removeCfgOnlyNodes (List<NestedObject> nos) {
    FilterOnlyMappedLines filter = new FilterOnlyMappedLines();
    List<NestedObject> filtered = new List<NestedObject>();
    for (NestedObject no : nos) {
      filtered.addAll(no.filter(filter));
    }
    return filtered;
  }

  public static List<NestedObject> removeMfgNodes (List<NestedObject> nos) {
    FilterOnlySalesLines filter = new FilterOnlySalesLines();
    List<NestedObject> filtered = new List<NestedObject>();
    for (NestedObject no : nos) {
      filtered.addAll(no.filter(filter));
    }
    return filtered;
  }

  public class FilterOnlySalesLines implements NestedObject.FilterFunction {
    public Boolean test(NestedObject.Nestable obj, Map<String, Object> data) {

      if(OrgSettings.LogikEnabled && ((NestedObject.NestableSObject) obj).obj.getSObjectType().getDescribe().getName() == 'LGK__ConfigurationBOM__c') {
       // return PWUtils.getField(obj, 'LGK__Type__c') == 'SALES';
      }
      return true;
      /*
      if(obj instanceof OrderItem) {
        try {
          return ((OrderItem) obj).SBQQ__QuoteLine__c != null;
        } catch (Exception e) {
          return true; // We cannot determine if this is a MFG or SALES item so don't exclude it.
        }
      }
      // Not an order line, assume quote line.
      return (!(obj instanceof LGK__ConfigurationBOM__c)) || ((LGK__ConfigurationBOM__c) obj).LGK__Type__c == 'SALES';
      */
    }
  }

  public class FilterOnlyMappedLines implements NestedObject.FilterFunction {
    public FilterOnlyMappedLines(){}
    public Boolean test(NestedObject.Nestable obj, Map<String,Object> data) {
      SObject objRecord = ((NestedObject.NestableSObject) obj).obj;
      return objRecord == null || objRecord instanceof OrderItem || objRecord instanceof SBQQ__QuoteLine__c;
    }
  }

  public class ConfigurationBOMException extends Exception {}

}