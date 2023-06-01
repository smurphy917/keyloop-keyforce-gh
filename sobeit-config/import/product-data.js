exports.build = (library, runtimeConfig) => {

    // runtimeConfig.environment    - All lowercase name of environment as known to Ant
    // runtimeConfig.instanceUrl    - Salesforce Instance URL to be used with Session Id for authentication
    // runtimeConfig.sessionId      - Salesforce Session Id to be used with Instance URL for authentication
    // runtimeConfig.dataDirectory  - Directory where data is stored

    return {
        
        target: {
            connectionType: "SalesforceSessionConnection",
            instanceUrl: runtimeConfig.instanceUrl,
            sessionId: runtimeConfig.sessionId,
            useBulkApi: true,
        },

        source: {
            connectionType  : 'JsonFileConnection',             // This is the type of connection to use as the target
            targetDirectory: runtimeConfig.dataDirectory + '/product-data'
        },

        move: [

            {
                objectName: 'SBQQ__ProductFeature__c',
                mapIdUsing: 'FeatureId__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__ConfiguredSKU__c',
                        lookupTarget: 'Product2',
                        lookupMappedFromId: 'ExternalId__c'
                    }
                ]
            },
            {
                objectName: 'SBQQ__ProductOption__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__ConfiguredSKU__c',
                        lookupTarget: 'Product2',
                        lookupMappedFromId: 'ExternalId__c'
                    },
                    {
                        fieldName: 'SBQQ__OptionalSKU__c',
                        lookupTarget: 'Product2',
                        lookupMappedFromId: 'ExternalId__c'
                    }
                ]
            },
            {
                objectName: 'SBQQ__ProductRule__c',
                postDelete: {
                    notInSourceFilter: true
                }
            },
            {
                objectName: 'SBQQ__AttributeSet__c',
            },
            {
                objectName: 'SBQQ__ConfigurationAttribute__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__Feature__c',
                        lookupTarget: 'SBQQ__ProductFeature__c',
                        lookupMappedFromId: 'FeatureId__c'
                    },
                    {
                        fieldName: 'SBQQ__Product__c',
                        lookupTarget: 'Product2',
                        lookupMappedFromId: 'ExternalId__c'
                    },
                    {
                        fieldName: 'RecordTypeId',
                        lookupTarget: 'RecordType',
                        lookupMappedFromId: 'DeveloperName'
                    }
                ]
            },
            {
                objectName: 'SBQQ__ProductAttribute__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__Attribute__c',
                        lookupTarget: 'SBQQ__ConfigurationAttribute__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    },
                    {
                        fieldName: 'SBQQ__AttributeSet__c',
                        lookupTarget: 'SBQQ__AttributeSet__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    }
                ]
            },
            {
                objectName: 'SBQQ__ProductAction__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__Product__c',
                        lookupTarget: 'Product2',
                        lookupMappedFromId: 'ExternalId__c'
                    },
                    {
                        fieldName: 'SBQQ__Rule__c',
                        lookupTarget: 'SBQQ__ProductRule__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    },
                    {
                        fieldName: 'SBQQ__ValueAttribute__c',
                        lookupTarget: 'SBQQ__ProductAttribute__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    }
                ],
                postDelete: {
                    notInSourceFilter: true
                }
            },
            {
                objectName: 'SBQQ__LookupQuery__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__ProductRule__c',
                        lookupTarget: 'SBQQ__ProductRule__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    },
                    {
                        fieldName: 'SBQQ__TestedConfigurationAttribute__c',
                        lookupTarget: 'SBQQ__ConfigurationAttribute__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    }
                ],
                recordFilters: [library.recordFilters.ifFieldIsNull('SBQQ__ProductRule__c')]
            },
            {
                objectName: 'SBQQ__SummaryVariable__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__CombineWith__c',
                        lookupTarget: 'SBQQ__SummaryVariable__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    }
                ]
            },
            {
                objectName: 'SBQQ__ErrorCondition__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__Rule__c',
                        lookupTarget: 'SBQQ__ProductRule__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    },
                    {
                        fieldName: 'SBQQ__TestedAttribute__c',
                        lookupTarget: 'SBQQ__ProductAttribute__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    },
                    {
                        fieldName: 'SBQQ__TestedVariable__c',
                        lookupTarget: 'SBQQ__SummaryVariable__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    }
                ]
            },
            {
                objectName: 'SBQQ__ConfigurationRule__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__Product__c',
                        lookupTarget: 'Product2',
                        lookupMappedFromId: 'ExternalId__c'
                    },
                    {
                        fieldName: 'SBQQ__ProductFeature__c',
                        lookupTarget: 'SBQQ__ProductFeature__c',
                        lookupMappedFromId: 'FeatureId__c'
                    },
                    {
                        fieldName: 'SBQQ__ProductRule__c',
                        lookupTarget: 'SBQQ__ProductRule__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    }
                ]
            },
            {
                objectName: 'SBQQ__CustomAction__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__ParentCustomAction__c',
                        lookupTarget: 'SBQQ__CustomAction__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    }
                ]
            },
            {
                objectName: 'SBQQ__CustomActionCondition__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__CustomAction__c',
                        lookupTarget: 'SBQQ__CustomAction__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    }
                ]
            },
            {
                objectName: 'SBQQ__SearchFilter__c',
                lookupMappings: [
                    {
                        fieldName: 'SBQQ__Action__c',
                        lookupTarget: 'SBQQ__CustomAction__c',
                        lookupMappedFromId: 'Source_System_Id__c'
                    }
                ]
            }
        ]
    }
};