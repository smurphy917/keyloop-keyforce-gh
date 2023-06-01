@isTest
public with sharing class PWUtilsTest {

    @TestSetup
    static void makeData(){
        Map<String,Map<String,Object>> overrides = new Map<String,Map<String,Object>>();
        Map<String,Object> accOverrides = new Map<String,Object>();
        accOverrides.put('RecordTypeId', Schema.SObjectType.Account.getRecordTypeInfosByName().get('Company').getRecordTypeId());
        accOverrides.put('Blocked__c', '');
        overrides.put('Account',accOverrides);
        String[] objects = new String[]{
            'Product2',
            'Pricebook2',
            'PricebookEntry',
            'Legal_Entity__c',
            'Account',
            'Opportunity',
            'SBQQ__Quote__c',
            'Order',
            'OrderItem'
        };
        TestUtility.loadData('testDataAssetManagement', objects, overrides);
    }

    @isTest
    static void getFieldTest() {
    //public static Object getField(SObject obj, String fieldPath) {


        Account a = [SELECT Id, Name, ParentId, Parent.Name FROM Account WHERE ParentId != null LIMIT 1];
        
        Test.startTest();
        String parentName = (String) PWUtils.getField(a, 'Parent.Name');
        Test.stopTest();
        System.assertEquals('Apex Test Account', parentName);
    }
    
    @isTest
    static void setFieldTest(){
    //public static Object setField(SObject obj, String fieldPath, Object value) {
        Account a = [SELECT Id, Name, ParentId, Parent.Name FROM Account WHERE ParentId != null LIMIT 1];
        PWUtils.setField(a, 'BillingCountry', 'GB');
        System.assertEquals('GB', a.BillingCountry);
        try {
            PWUtils.setField(a,'BogusField','some value');
        } catch (Exception e) {
            System.assert(e instanceof PWUtils.FieldUpdateException);
        }
    }

    @isTest
    public static void hasFieldTest(){
    // public static Boolean hasField(String objectName, String fieldName) {
        System.assert(PWUtils.hasField('Account','BillingCountry'));
        System.assert(!PWUtils.hasField('Account','BogusField__c'));
        try {
            PWUtils.hasField('BogusObj', 'field');
            System.assert(false);
        } catch (Exception e) {
            System.assert(e instanceof PWUtils.DescribeException);
        }
    }

    @isTest
    public static void sliceTest() {
    // public static List<Object> slice (List<Object> objList, Integer startIdx, Integer endIdx) {
       String[] strs = new String[]{
        'a',
        'b',
        'c',
        'd',
        'e'
       };
       System.assertEquals(new String[]{'c','d'}, PWUtils.slice(strs,2,4));
       System.assertEquals(new String[]{'d','e'}, PWUtils.slice(strs,3));
       System.assertEquals(new String[]{'a','b','c'}, PWUtils.slice(strs, null, 3));
    }

    @isTest
    public static void selectStarTest() {

    // public static List<SObject> selectStar(
    //     String sobjectName,
    //     String whereClause,
    //     String[] expandFields
    // ) {
        List<Account> accts = (List<Account>) PWUtils.selectStar('Account','ParentId = null AND Name != \'[DELETED ASSETS]\'',new String[]{'(SELECT Id FROM Opportunities)'});
        System.assertEquals(2,accts.size());
        System.assertNotEquals(null, accts[0].Name);
        System.assertNotEquals(0, accts[0].Opportunities.size());
    }

    @isTest
    public static void getFieldsForObjectTest() {
    // public static List<String> getFieldsForObject (String objectName) {
        List<String> accFields = PWUtils.getFieldsForObject('Account');
        System.assertNotEquals(0, accFields.size());
    }

    @isTest
    public static void getCommonFieldsTest() {
    // public static List<String> getCommonFields (String objA, String objB) {
        List<String> fields = PWUtils.getCommonFields('Account','Opportunity');
        System.assertNotEquals(0,fields.size());
        System.assert(fields.contains('name'));
    }

    @isTest
    public static void getSetFromMapTest() {
    // public static Object getSetFromMap (Map<Object, Object> parent, String key, Object defaultVal) {
        Map<String,String> m =  new Map<String,String>();
        m.put('test', 'val');
        String t1 = (String) PWUtils.getSetFromMap(m, 'test', 'other val');
        String t2 = (String) PWUtils.getSetFromMap(m, 'test2', 'new val');
        System.assertEquals('val', t1);
        System.assertEquals('new val', t2);
        System.assertEquals('new val', m.get('test2'));
    }

    @isTest
    public static void twinFieldsTest() {
        OrderItem baseOi = [SELECT Id FROM OrderItem LIMIT 1];
        OrderItem oi = (OrderItem) PWUtils.selectStar('OrderItem', 'Id = \'' + baseOi.Id + '\'')[0];
        Asset a = new Asset();
        PWUtils.twinFields(oi, a);
        System.assertEquals(oi.Product2Id, a.Product2Id);
        System.assertEquals(oi.SBQQ__ChargeType__c, a.SBQQ__ChargeType__c);
        Asset a2 = new Asset();
        PWUtils.twinFields(oi, a2, new String[]{'Product2Id'});
        System.assertNotEquals(oi.Product2Id, a2.Product2Id);
    }

    @isTest
    public static void sumEntriesTest() {
        Map<String,Double> m1 = new Map<String,Double>();
        Map<String,Double> m2 = new Map<String,Double>();

        m1.put('a',10);
        m1.put('b',20);

        m2.put('b',30);
        m2.put('c',40);

        Map<String,Double> summed = PWUtils.sumEntries(m1, m2);

        System.assertEquals(10,summed.get('a'));
        System.assertEquals(50,summed.get('b'));
        System.assertEquals(40,summed.get('c'));
    }

    @isTest
    public static void standardPricebookIdTest() {
        // PWUtils.standardPricebookId = Test.getStandardPricebookId();
        System.assertEquals(Test.getStandardPricebookId(),PWUtils.standardPricebookId);
        Id testPricebookId = TestUtility.getFakeId(Schema.Pricebook2.getSObjectType());
        PWUtils.standardPricebookId = testPricebookId;
        system.assertEquals(testPricebookId, PWUtils.standardPricebookId);
    }

    @isTest
    public static void testProrate(){
        Date d1 = Date.newInstance(2023,4,1);
        Date d2 = Date.newInstance(2023,8,12);
        Decimal mrr = 200;
        Decimal amt = PWUtils.prorate(200, PWUtils.Period.MONTH, d1, d2, PWUtils.ProrationMethod.MONTHLY_DAILY);
        // 4 months, 12 days
        System.assertEquals((mrr * 4 + (12.0 / (365.0/12.0)) * mrr).setScale(4),amt.setScale(4));
    }
    @isTest
    public static void testUnprorate(){
        Date d1 = Date.newInstance(2023,4,1);
        Date d2 = Date.newInstance(2023,8,12);
        Decimal amt = 219.726;
        Decimal mrr = PWUtils.unprorate(amt, d1, d2, PWUtils.ProrationMethod.MONTHLY_DAILY, PWUtils.Period.MONTH);
        // 4 months, 12 days
        System.assertEquals(50,mrr.setScale(4));
    }
    @isTest
    public static void monthsDaysBetwenTest() {
        Date d1 = Date.newInstance(2023,1,1);

        // same date
        System.assertEquals(new Integer[]{0,1}, PWUtils.monthsDaysBetween(d1,d1));
        // Month + partial
        System.assertEquals(new Integer[]{4,5}, PWUtils.monthsDaysBetween(d1,d1.addMonths(4).addDays(4)));
        // Month + partial next month
        System.assertEquals(new Integer[]{3,25}, PWUtils.monthsDaysBetween(d1.addDays(10),d1.addMonths(4).addDays(4)));
        // Whole months
        System.assertEquals(new Integer[]{4,0}, PWUtils.monthsDaysBetween(d1.addDays(10),d1.addMonths(4).addDays(9)));
    }
}