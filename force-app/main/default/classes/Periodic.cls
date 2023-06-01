public interface Periodic {
    Datetime getStart();
    Datetime getEnd();
    void setStart(Datetime startDate);
    void setEnd(Datetime endDate);
    // Map<String,Double> getValues(Datetime startDate, Datetime endDate);
    Map<String,Double> getValues();
    void setValues(Map<String,Double> vals);
    Boolean equals(Periodic period);
    void setValue(String key, Double val);

}