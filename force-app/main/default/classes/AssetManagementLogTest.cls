@isTest
public with sharing class AssetManagementLogTest {
    @TestSetup
    static void makeData(){
        String[] objects = new String[]{
            'CustomNotificationType'
        };
        TestUtility.loadData('testDataAssetManagement', objects);
    }
    @isTest
    public static void testError(){
        try {
            AssetManagementLog.logError(new TestException('Test Error'),null,'Manual');
        } catch (Exception e) {
            System.assert(e instanceof TestException);
            System.assertEquals('Test Error', e.getMessage());
        }
    }
    @isTest
    public static void testBatch(){
        AssetManagementLog.logBatch(
            null,
            'Manual',
            4,
            new Exception[]{
                new TestException('Test error')
            }
        );
    }
    public class TestException extends Exception{}
}