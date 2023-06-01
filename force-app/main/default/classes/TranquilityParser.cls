public with sharing class TranquilityParser {
    public TranquilityParser() {}
    public static Tranquility.AssetRequest parseRequest(String jsonStr, System.Type type) {
        Tranquility.AssetRequest req = (Tranquility.AssetRequest) JSON.deserialize(jsonStr, type);
        req.assetActionSources = new List<Tranquility.AssetActionSourceInput>();
        JSONParser parser = JSON.createParser(jsonStr);
        // Start at the root object
        while (parser.nextToken() != null) {
            if (parser.getCurrentToken() == JSONToken.START_OBJECT) {
                // Clear parsed asset action sources
                while (parser.nextToken() != null) {
                    if(parser.getCurrentToken() == JSONToken.FIELD_NAME && parser.getText() == 'assetActionSources') {
                        while(parser.nextToken() != null) {
                            // recurse into assetActionSources
                            if(parser.getCurrentToken() == JSONToken.START_ARRAY) {
                                while (parser.nextToken() != null) {
                                    if(parser.getCurrentToken() == JSONToken.START_OBJECT) {
                                        // single instance
                                        String key;
                                        Map<String,Object> staged = new Map<String,Object>();
                                        System.Type aasType;
                                        while (parser.nextToken() != null) {
                                            if(parser.getCurrentToken() == JSONToken.FIELD_NAME) {
                                                key = parser.getText();
                                                 if(key == 'referenceEntityItem') {
                                                    aasType = Tranquility.ReferencedAssetActionSourceInput.class;
                                                } else if (key == 'externalReference') {
                                                    aasType = Tranquility.NonReferencedAssetActionSourceInput.class;
                                                }
                                            } else if (parser.getCurrentToken() == JSONToken.END_OBJECT) {
                                                // finalised
                                                req.assetActionSources.add(
                                                    (Tranquility.AssetActionSourceInput)JSON.deserialize(JSON.serialize(staged), aasType)
                                                );
                                            }else {
                                                // value type
                                                switch on parser.getCurrentToken() {
                                                    when VALUE_STRING {
                                                        staged.put(key, parser.getText());
                                                    }
                                                    when VALUE_NUMBER_INT {
                                                        staged.put(key, parser.getIntegerValue());
                                                    }
                                                    when VALUE_NUMBER_FLOAT {
                                                        staged.put(key, parser.getDoubleValue());
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return req;
    }
}