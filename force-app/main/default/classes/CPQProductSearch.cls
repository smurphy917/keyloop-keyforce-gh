global with sharing class CPQProductSearch implements SBQQ.ProductSearchPlugin {
    global Boolean isSearchCustom(SObject quote, Map<String,Object> fieldValuesMap) {
        return false;
    }
    global Boolean isFilterHidden(SObject quote, String fieldName) {
        return true;
    }
    global Boolean isInputHidden(SObject quote, String fieldName) {
        return true;
    }
    global Object getFilterDefaultValue(SObject quote, String fieldName) {
        return null;
    }
    global String getAdditionalSearchFilters(SObject quote, Map<String, Object> fieldValuesMap) {
        if(true){
            return null;
        }
        if(fieldValuesMap.keySet().size() > 0) {
            System.debug('FIELD VALUES MAP:\n' + JSON.serialize(fieldValuesMap));
        }
        SBQQ__Quote__c quoteObj = (SBQQ__Quote__c) quote;
        Account acct = [
            SELECT Id, Legal_Entity__c
            FROM Account
            WHERE Id = :quoteObj.SBQQ__Account__c
        ];
        String[] conditions = new String[]{};
        if(acct.Legal_Entity__c != null) {
            conditions.add('Legal_Entity__c = \'' + acct.Legal_Entity__c + '\'');
        }
        conditions.add('Customer__c = \'' + quoteObj.SBQQ__Account__c + '\''); // TODO handle hierarchies
        String[] mfgCodes = new String[]{};
        String[] makeIds = new String[]{};
        List<Account_Make_JO__c> accountMakes = [
            SELECT Id, Make__c, Manufacturer_Code__c
            FROM Account_Make_JO__c
            WHERE Account__c IN (
                SELECT Id
                FROM Account
                WHERE ParentId = :quoteObj.SBQQ__Account__c // TODO handle hierarchies
            )
        ];
        for (Account_Make_JO__c accountMake : accountMakes) {
            if(accountMake.Manufacturer_Code__c != null && !mfgCodes.contains(accountMake.Manufacturer_Code__c)) {
                mfgCodes.add(accountMake.Manufacturer_Code__c);
            }
            if(accountMake.Make__c != null && !makeIds.contains(accountMake.Make__c)) {
                makeIds.add(accountMake.Make__c);   
            }
        }
        if(mfgCodes.size() > 0) {
            conditions.add('Manufacturer_Code__c IN (\'' + String.join(mfgCodes, '\',\'') + '\')');
        }
        if(makeIds.size() > 0) {
            conditions.add('Make__c IN (\'' + String.join(makeIds, '\',\'') + '\')');
        }
        String conjunction = '';
        if(fieldValuesMap.keySet().size() > 0) {
            conjunction = ' AND ';
        }
        String additionalFilters = conjunction + 'Product2Id IN (SELECT Product__c FROM Product_Availability__c WHERE Availability__c != \'Not Available\' AND (' + String.join(conditions, ' OR ') + '))';
        System.debug('ADDITIONAL FILTERS:\n' + additionalFilters);
        return additionalFilters;
    }
    global List<PricebookEntry> search(SObject quote, Map<String,Object> fieldValuesMap){ 
        // Get all possible filter fields from the search filter field set
        List<Schema.FieldSetMember> searchFilterFieldSetFields = SObjectType.Product2.FieldSets.SBQQ__SearchFilters.getFields();
        // Get all possible fields from the search result field set
        List<Schema.FieldSetMember> searchResultFieldSetFields = SObjectType.Product2.FieldSets.SBQQ__SearchResults.getFields();
        // Build the Select string
        String selectClause = 'SELECT ';
        for(Schema.FieldSetMember field : searchResultFieldSetFields) {
            selectClause += 'Product2.' + field.getFieldPath() + ', ';
        }
        selectClause += 'Id, UnitPrice, Pricebook2Id, Product2Id, Product2.Id';
        // Build the Where clause
        String whereClause = '';
        for(Schema.FieldSetMember field : searchFilterFieldSetFields) {
            if(!fieldValuesMap.containsKey(field.getFieldPath())) {
            continue;
            }
            if(field.getType() == Schema.DisplayType.String || field.getType() == Schema.DisplayType.Picklist) {
            whereClause += 'Product2.' + field.getFieldPath() + ' LIKE \'%' + fieldValuesMap.get(field.getFieldPath()) + '%\' AND ';
            }
        }
        whereClause += 'Pricebook2Id = \'' + quote.get('SBQQ__Pricebook__c') + '\'';
        // Build the query
        String query = selectClause + ' FROM PricebookEntry WHERE ' + whereClause;
        // Perform the query
        List<PricebookEntry> pbes = new List<PricebookEntry>();
        pbes = Database.query(query);
        return pbes;
    }
    global Boolean isSuggestCustom(SObject quote, Map<String,Object> fieldValuesMap) {
        return false;
    }
    global String getAdditionalSuggestFilters(SObject quote, Map<String,Object> fieldValuesMap) {
        return null;
    }
    global List<PricebookEntry> suggest(SObject quote, Map<String,Object> fieldValuesMap) {
        return null;
    }
    global Object getInputDefaultValue(SObject quote, String fieldName) {
        return null;
    }

}