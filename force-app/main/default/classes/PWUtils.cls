global class PWUtils {

    public enum ProrationMethod {
        MONTHLY_DAILY,
        DAY
    }

    public enum Period {
        MONTH,
        YEAR
    }

    public enum DMLOperation {
        DML_UPDATE,
        DML_INSERT,
        DML_DELETE
    }

    private static Id stdPbId;
    global static Map<String,SObjectType> globalDescribe;
    private static Map<String,Map<String,Schema.DisplayType>> fieldDescribes = new Map<String,Map<String,Schema.DisplayType>>();

    public static Id standardPricebookId {
        get {
            if(stdPbId != null) {
                return stdPbId;
            }
            if(Test.isRunningTest()){
                stdPbId = Test.getStandardPricebookId();
                return stdPbId;
            }
            Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true];
            stdPbId = pb.Id;
            return pb.Id;
        }
        set {
            if(!Test.isRunningTest()){
                throw new PWUtilsException('Cannot set the standard pricebook id.');
            }
            stdPbId = value;
        }
    }
    
    public static Object getField(SObject obj, String fieldPath) {
        String[] fieldPathComponents = fieldPath.split('\\.');
        Object fieldVal = null;
        if(fieldPathComponents.size() == 1) {
          fieldVal = obj.get(fieldPath);
        } else if(fieldPathComponents.size() > 1) {
          SObject relatedObj = obj.getSObject(fieldPathComponents[0]);
          if(relatedObj != null) {
            fieldVal = getField(relatedObj, String.join(slice(fieldPathComponents,1,null), '.'));
          }
        }
        return fieldVal;
    }

    public static Object setField(SObject obj, String fieldPath, Object value) {
        if(fieldIsEditable(String.valueOf(obj.getSObjectType()), fieldPath)) {
            if(value instanceof SObject) {
                return obj.putSObject(fieldPath, (SObject) value);
            } else {
                return obj.put(fieldPath, value);
            }
        }
        throw new FieldUpdateException('Object [' + String.valueOf(obj.getSObjectType()) + '] does not contain field [' + fieldPath + '] or the field is not updateable.');
    }

    private static void initDescribe() {
        if(globalDescribe == null) {
            globalDescribe = Schema.getGlobalDescribe();
        }
    }

    public static Boolean hasField(String objectName, String fieldName) {
        initDescribe();   
        if(globalDescribe.containsKey(objectName)) {
            return globalDescribe.get(objectName).getDescribe().fields.getMap().keySet().contains(fieldName.toLowerCase());
        }
        throw new DescribeException('Objct [' + objectName + '] not present in global describe result.');
    }

    public static Boolean fieldIsEditable(String objectName, String fieldName) {
        initDescribe();   
        if(globalDescribe.containsKey(objectName)) {
            Map<String,Schema.SObjectField> fieldMap = globalDescribe.get(objectName).getDescribe().fields.getMap();
            return fieldMap.keySet().contains(fieldName.toLowerCase()) && fieldMap.get(fieldName.toLowerCase()).getDescribe().isUpdateable();
        }
        throw new DescribeException('Objct [' + objectName + '] not present in global describe result.');
    }

    public static List<Object> slice (List<Object> objList, Integer startIdx) {
        return slice(objList, startIdx, null);
    }

    public static List<Object> slice (List<Object> objList, Integer startIdx, Integer endIdx) {
        if(startIdx == null) {
            startIdx = 0;
        }
        if(endIdx == null || endIdx == -1) {
            endIdx = objList.size();
        }
        List<Object> result = objList.clone();
        result.clear();
        for (Integer i = startIdx; i < endIdx; i++) {
            result.add(objList.get(i));
        }
        return result;
    }

    public static List<SObject> selectStar (
        String sobjectName,
        String whereClause
    ) {
        return selectStar(sobjectName, whereClause, new String[]{});
    }

    public static List<SObject> selectStar(
        String sobjectName,
        String whereClause,
        String[] expandFields
    ) {
        Set<String> fieldNames = schema.describeSObjects(
            new List<String>{ sobjectName }
        )[0]
        .fields.getMap()
        .keyset();
        List<String> iterableFields = new List<String>(fieldNames);
        if(expandFields != null) {
            iterableFields.addAll(expandFields);
        }

        String query = String.format(
            'SELECT {0} FROM {1} WHERE {2}',
            new List<String>{
            String.join(iterableFields, ','),
            sobjectName,
            whereClause
            }
        );

        return Database.query(query);
    }

    public static List<String> getFieldsForObject (String objectName) {
        return new List<String>(getFieldsMapForObject(objectName).keySet());
    }

    public static Map<String,SObjectField> getFieldsMapForObject (String objectName) {
        initDescribe();
        return globalDescribe.get(objectName).getDescribe().fields.getMap();
    }

    public static SObjectType getSObjectType (String objectName) {
        initDescribe();
        return globalDescribe.get(objectName);
    }

    public static Map<String,Schema.DisplayType> getFieldTypesForObject (String objectName) {
        if(fieldDescribes.containsKey(objectName)) {
            return fieldDescribes.get(objectName);
        } else {
            Map<String,Schema.DisplayType> objFields = new Map<String,Schema.DisplayType>();
            Map<String,SObjectField> fields = getFieldsMapForObject(objectName);
            for(String fieldName : fields.keySet()) {
                objFields.put(fieldName, fields.get(fieldName).getDescribe().getType());
            }
            fieldDescribes.put(objectName, objFields);
            return objFields;
        }
    }

    public static List<String> getCommonFields (String objA, String objB) {
        return getCommonFields(objA, objB, false);
    }

    public static List<String> getCommonFields (String objA, String objB, Boolean updateableOnly) {
        List<String> exclude = new List<String>(new String[]{
            'id',
            'createddate',
            'createdbyid',
            'lastmodifieddate',
            'lastmodifiedbyid',
            'systemmodstamp',
            'isdeleted',
            'currencyisocode',
            'parentid',
            'ownerid',
            'lastactivitydate',
            'lastvieweddate',
            'lastreferenceddate'
        });
        Map<String,SObjectField> objAFields = getFieldsMapForObject(objA);
        Map<String,SObjectField> objBFields = getFieldsMapForObject(objB);
        List<String> objAFieldKeys = new List<String>(objAFIelds.keySet());
        List<String> objBFieldKeys = new List<String>(objBFIelds.keySet());

        List<String> common = new List<String>();
        for (String aField : objAFieldKeys) {
            if(exclude.contains(aField)){
                continue;
            }
            if(objBFieldKeys.contains(aField)){
                DescribeFieldResult aFld = objAFields.get(aField).getDescribe();
                DescribeFieldResult bFld = objBFields.get(aField).getDescribe();
                if(aFld.getType() == bFld.getType() && (!updateableOnly || bFld.isUpdateable())) {
                    common.add(aField);
                }
            }
        }
        return common;
    }

    public static Object getSetFromMap (Map<String, Object> parent, String key, Object defaultVal) {
        Object val = parent.get(key);
        if(val == null) {
            parent.put(key, defaultVal);
            return parent.get(key);
        }
        return val;
    }

    public static void twinFields(SObject source, SObject target) {
        twinFields(source, target, new String[]{});
    }

    public static void twinFields(StagedRecord source, StagedRecord target) {
        twinFields(source, target, new String[]{});
    }

    public static void twinFields(SObject source, SObject target, List<String> excludeFields) {
        String[] lowerExclFields = new String[]{};
        for (String field : excludeFields) {
            lowerExclFields.add(field.toLowerCase());
        }
        List<String> fields = getCommonFields(source.getSObjectType().getDescribe().getName(), target.getSObjectType().getDescribe().getName(), true);
        for (String field : fields) {
            if(!lowerExclFields.contains(field)) {
                setField(target, field, getField(source, field));
            }
        }
    }

    public static void twinFields(StagedRecord source, StagedRecord target, List<String> excludeFields) {
        String[] lowerExclFields = new String[]{};
        for (String field : excludeFields) {
            lowerExclFields.add(field.toLowerCase());
        }
        System.assertNotEquals(null, source);
        System.assertNotEquals(null, target);
        List<String> fields = getCommonFields(source.getType(), target.getType(), true);
        for (String field : fields) {
            if(!lowerExclFields.contains(field)) {
                target.set(field, source.get(field));
            }
        }
    }

    public static Map<String,Double> sumEntries (Map<String,Double> objA, Map<String,Double> objB) {
        return sumEntries(objA, objB, new String[]{});
    }
        

    public static Map<String,Double> sumEntries (Map<String,Double> objA, Map<String,Double> objB, String[] ignoreKeys) {
        Set<String> keys = new Set<String>();
        keys.addAll(objA.keySet());
        keys.addAll(objB.keySet());
        Map<String,Double> result = new Map<String,Double>();
        for (String key : keys) {
            if(ignoreKeys != null && ignoreKeys.contains(key)) {
                continue;
            }
            Double val = 0.0;
            if(objA.containsKey(key)) {
                val += objA.get(key);
            }
            if(objB.containsKey(key)) {
                Double toAdd = objB.get(key);
                if(toAdd != null) {
                    val += toAdd;
                }
            }
            result.put(key, val);
        }
        return result;
    }

    public static SObject assign(SObject target, SObject source) {
        System.assertEquals(target.getSObjectType(), source.getSObjectType());
        Map<String,Object> fieldMap = source.getPopulatedFieldsAsMap();
        for(String key : fieldMap.keySet()) {
            try {
                if(hasField(String.valueOf(source.getSObjectType()), key)) {
                    setField(target, key, getField(source, key));
                }
            } catch (FieldUpdateException e) {}
        }
        return target;
    }

    public static Object find(List<Object> objList, FindFunction func) {
        for (Object obj : objList) {
            if(func.test(obj)) {
                return obj;
            }
        }
        return null;
    }

    public static Integer findIndex(List<Object> objList, FindFunction func) {
        Integer idx = -1;
        for (Object obj : objList) {
            idx++;
            if(func.test(obj)) {
                return idx;
            }
        }
        return -1;
    }

    public static Boolean isId(String key) {
        if(key == null) {
            return false;
        }
        try {
            ((Id) key).getSObjectType();
            return true;
        } catch (StringException e) {
            return false;
        }
    }

    public static String getIdFieldForRef(String ref) {
        if(ref.endsWith('__r')) {
            return ref.replace('__r', '__c');
        } else {
            return ref + 'Id';
        }
    }
    
    public static Integer[] monthsDaysBetween (Date d1, Date d2) {
        Integer months = d1.monthsBetween(d2.addDays(1));
        Integer days = 0;
        if(d1.day() > d2.addDays(1).day()) {
            months--;
        }
        if (d1.day() != d2.addDays(1).day()) {
            if(d1.day() > d2.day()) {
                if(d2.month() > 1) {
                    // 18/10 -> 6/11 --- 6 + 31 - 18 + 1;
                    days = d2.day() + Date.daysInMonth(d2.year(), d2.month() - 1) - d1.day() + 1;
                } else {
                    days = d2.day() + Date.daysInMonth(d2.year() - 1, 12) - d1.day() + 1;
                }
            } else if (d2.day() > d1.day() ) {
                days = d2.day() - d1.day() + 1;
            } else {
                days = 1;
            }
        }
        return new Integer[]{months, days};
    }

    public static Double prorate(Decimal amount, Period pd, Date startDate, Date endDate, ProrationMethod method) {
        switch on method {
            when MONTHLY_DAILY {
                Integer[] diffs = monthsDaysBetween(startDate, endDate);
                Integer wholeMonths = diffs[0];
                Decimal monthPart = diffs[1] / (365.0 / 12.0);
                switch on pd {
                    when YEAR {
                        return amount * ((wholeMonths + monthPart) / 12.0);
                    }
                    when MONTH {
                        return amount * (wholeMonths + monthPart);
                    }
                }
            }
        }
        return null;
    }

    public static Double unprorate(Decimal proratedAmount, Date startDate, Date endDate, ProrationMethod method, Period pd) {
        if(proratedAmount == null) {
            return null;
        }
        switch on method {
            when MONTHLY_DAILY {
                Integer[] diffs = monthsDaysBetween(startDate, endDate);
                Integer wholeMonths = diffs[0];
                Decimal monthPart = diffs[1] / (365.0 / 12.0);
                switch on pd {
                    when MONTH {
                        return proratedAmount / (wholeMonths + monthPart);
                    }
                    when YEAR {
                        return proratedAmount / ((wholeMonths + monthPart) / 12.0);
                    }
                }
            }
        }
        return null;
    }
    
    public class DescribeException extends Exception {}

    public class FieldUpdateException extends Exception {}

    public interface FindFunction {
        Boolean test(Object obj);
    }

    public static List<Object> Filter(List<Object> items, FilterFunction fn) {
        List<Object> filtered = new List<Object>();
        for (Object item : items) {
            if(fn.filter(item)){
                filtered.add(item);
            }
        }
        return filtered;
    }

    public interface FilterFunction {
        Boolean filter(Object item);
    }

    public static Decimal mod (Decimal input, Decimal base) {
        Decimal div = input / base;
        return (div - Integer.valueOf(div)) * base;
    }

    public static void validateDML (DMLOperation op, List<SObject> records) {
        List<String> requiredFields = new List<String>();
        List<String> excludedFields = new List<String>();
        switch on op {
            when DML_INSERT {
                excludedFields.add('id');
            }
            when DML_UPDATE {
                requiredFields.add('id');
            }
            when DML_DELETE {
                requiredFields.add('id');
            }
        }
        System.debug('OPERATION: ' + op.name());
        System.debug('RECORDS: ' + JSON.serialize(records));
        for (SObject rec : records) {
            for (String fld : requiredFields) {
                System.assertNotEquals(null, rec.get(fld), 'Required field missing on record: ' + fld + '; Operation: ' + op.name() + '; Record: ' + JSON.serialize(rec));
            }
            for (String fld : excludedFields) {
                System.assertEquals(null, rec.get(fld), 'Excluded field included on record: ' + fld + '; Operation: ' + op.name() + '; Record: ' + JSON.serialize(rec));
            }
        }
    }

    private class PWUtilsException extends Exception {}

}