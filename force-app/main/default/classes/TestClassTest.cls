@isTest
public class TestClassTest {
    @isTest
    public static void test() {
        TestUtility.loadData(
            'testDataAssetManagement',
            new String[]{
                'Profile',
                'User',
                'Legal_Entity__c',
                'Account'
            }
        );
    }
}