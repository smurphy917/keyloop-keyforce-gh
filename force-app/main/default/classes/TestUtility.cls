/**
* Apex method to generate fake record ids in tests
* Created by Stephen Willcock
* https://foobarforce.com/2013/08/15/apex-method-of-the-day-string-repeat/
*/
public class TestUtility
{
  static Integer s_num = 1;
  
  public static String getFakeId(Schema.SObjectType sot)
  {
    String result = String.valueOf(s_num++);
    return sot.getDescribe().getKeyPrefix() +
      '0'.repeat(12-result.length()) + result;
  }
  public static List<SObject> loadData(String prefix, List<String> objectNames) {
    return loadData(prefix, objectNames, new Map<String,Map<String,Object>>());
  }
  public static List<SObject> loadData(String prefix, List<String> objectNames, Map<String, Map<String, Object>> overrides) {
    List<SObject> allRecords = new List<SObject>();
    for (String objName : objectNames) {
      SObjectType objType = ((SObject) Type.forName(objName).newInstance()).getSObjectType();
      String fileObjName = objName.replace('__','');
      String nameStart = prefix + fileObjName + '%';
      String regex = prefix+fileObjName+'[0-9]*';
      Boolean fileFound = false;
      List<StaticResource> resources = [SELECT Name FROM StaticResource WHERE Name LIKE :nameStart ORDER BY Name];
      for (StaticResource resource : resources) {
        if(!Pattern.matches(regex,resource.Name)) {
          continue;
        }
        try {
          fileFound = true;
          List<SObject> records = Test.loadData(objType, resource.Name);
          Map<String,Object> objOverrides = overrides.get(objName);
          Map<String,Object> rscOverrides = overrides.get(resource.Name);
          if(objOverrides != null) {
            for (SObject record : records) {
              for (String key : objOverrides.keySet()) {
                record.put(key, objOverrides.get(key));
              }
            }
            update records;
          }
          if(rscOverrides != null) {
            for (SObject record : records) {
              for (String key : rscOverrides.keySet()) {
                record.put(key, rscOverrides.get(key));
              }
            }
            update records;
          }
          if(objName == 'Product2') {
            // Special case: add standard PBEs for Product2 records
            // ConnectApi.OrganizationSettings  orgSettings = ConnectApi.Organization.getSettings();
            List<PricebookEntry> pbes = new List<PricebookEntry>();
            for (Product2 p : (List<Product2>) records) {
              pbes.add(new PricebookEntry(
                Product2Id=p.Id,
                Pricebook2Id=Test.getStandardPricebookId(),
                CurrencyIsoCode='GBP', // orgSettings.features.defaultCurrencyIsoCode,
                UnitPrice=0,
                IsActive=true
              ));
            }
            insert pbes;
          }
          allRecords.addAll(records);
        } catch (Exception e) {
          if(Test.isRunningTest()) {
            // System.debug(JSON.serialize(allRecords));
            for(SObject record : allRecords) {
              List<SObject> recs = PWUtils.selectStar(record.getSObjectType().getDescribe().getName(), 'Id = \'' + record.Id + '\'');
              // SObject rec = Database.query(
              //   'SELECT FIELDS(STANDARD) FROM ' + record.getSObjectType().getDescribe().getName() + ' WHERE Id = \'' + record.Id + '\' LIMIT 1'
              // );
              System.debug(JSON.serialize(recs[0]));
            }
          }
          TestUtilityException ex = new TestUtilityException('Error loading data from resource [' + resource.Name + ']\n' + e.getMessage());
          ex.initCause(e);
          throw ex;
        }
      }
      if(!fileFound) {
        throw new TestUtilityException('No static resources found for obj [' + objName + ' : ' + fileObjName + ']');
      }
    }
    System.debug('TEST RECORDS LOADED:\n'+JSON.serialize(allRecords));
    return allRecords;
  }
  public class TestUtilityException extends Exception{}
}