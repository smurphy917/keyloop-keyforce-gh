@isTest
public with sharing class NestedObjectTest {
    @TestSetup
    static void makeData(){
        TestUtility.loadData(
            'testDataAssetManagement',
            new String[]{
                'Legal_Entity__c',
                'Account'
            }
        );
    }
    @isTest
    static void findTest() {
        NestedObject n = new NestedObject(
            [SELECT Id, ParentId, Name FROM Account],
            'Id',
            'ParentId'
        );
        NestedObject found = n.find(new FindByName('Apex Test Child Account'));
        NestedObject notFound = n.find(new FindByName('Bogus  Name'));
        System.assertNotEquals(null, found);
        System.assertEquals(null, notFound);
    }
    @isTest
    static void sanitiseTest() {
        NestedObject n = new NestedObject(
            [SELECT Id, ParentId, Name FROM Account],
            'Id',
            'ParentId'
        );
        NestedObject.SanitisedNestedObject clean = n.sanitise();
    }

    public class FindByName implements NestedObject.FilterFunction {
        private String name;
        public FindByName(String name) {
            this.name = name;
        }
        public Boolean test(NestedObject.Nestable obj, Map<String,Object> data) {
            return obj.get('Name') == this.name;
        }
    }
}