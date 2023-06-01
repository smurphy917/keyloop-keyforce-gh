@isTest
public class ThrowErrorTest {
    @isTest
    public static void test() {
        ThrowError.InvocableParameter p = new ThrowError.InvocableParameter();
        p.message = 'TEST message';
        try {
            ThrowError.InvocableThrowException(new List<ThrowError.InvocableParameter>{p});
        } catch (Exception e){
            System.assertEquals('TEST message', e.getMessage());
        }
    }
}