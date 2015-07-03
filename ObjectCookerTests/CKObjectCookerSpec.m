//
//  CKObjectCookerTests.m
//
//  Created by Cristian Kocza on 14/11/13.
//
//

#import <objc/objc.h>
#import <objc/runtime.h>
#import "CKObjectCooker.h"
#import "Kiwi.h"

@interface CKClassToInject : NSObject
@end

@implementation CKClassToInject
@end

@interface CKAnotherClassToInject : NSObject
@end

@implementation CKAnotherClassToInject
@end


@interface CKInjectedClass: NSObject
@property CKClassToInject *dependency;
@property int anInt;
@property NSObject *dummy;
@property(readonly) char *someChar;
@property(nonatomic, getter = retrieveTheName, setter = updateTheName:) NSString *name;
@end

@implementation CKInjectedClass

- (id)initWithInt:(int)val{
    if(self = [super init]){
        
    }
    return self;
}

- (id)init{
    return [super init];
}

@end

@interface CKInjectedClass2: NSObject
@property(setter = updateDependency:) CKClassToInject *customSetterDependency;
@property(atomic,strong,readonly) NSDictionary *customDictionary;
@end

@implementation CKInjectedClass2
@end

@interface CKDerivedInjectedClass: CKInjectedClass
@property CKAnotherClassToInject *otherDependency;
@end

@implementation CKDerivedInjectedClass
@end


SPEC_BEGIN(ObjectCookerTests)
__block CKObjectCooker *masterChef = nil;

beforeEach(^{
    masterChef = [CKObjectCooker new];
});

it(@"doesn't allow registration of nil classes",^{
    @try{
        [masterChef registerClass:nil withOptions:0];
        fail(@"No exception thrown");
    }@catch(NSException *ex){
        
    }
});

it(@"doesn't allow registration of meta classes",^{
    @try{
        [masterChef registerClass:object_getClass([self class]) withOptions:0];
        fail(@"No exception thrown");
    }@catch(NSException *ex){
        
    }
});

it(@"doesn't allow registration of its own", ^{
    @try{
        [masterChef registerClass:[CKObjectCooker class] withOptions:0];
        fail(@"No exception thrown");
    }@catch(NSException *ex){
        
    }
});

it(@"allows instance registration of nil instance", ^{
    @try{
        [masterChef registerInstance:nil forClass:[CKInjectedClass class]];
    }@catch(NSException *ex){
        fail(@"Exception thrown");
    }
});

void (^validateMultipleRegistrations)() = ^{
    it(@"fails when registering class with options 0",^{
        @try{
            [masterChef registerClass:[CKInjectedClass class] withOptions:0];
            fail(@"No exception thrown");
        }@catch(NSException *ex){
            
        }
    });
    
    it(@"fails when registering class with options singleton",^{
        @try{
            [masterChef registerClass:[CKInjectedClass class] withOptions:CKObjectCookerRegisterClassOptionSingleton];
            fail(@"No exception thrown");
        }@catch(NSException *ex){
            
        }
    });
    
    it(@"fails when registering instance",^{
        @try{
            [masterChef registerInstance:[NSObject new] forClass:[CKInjectedClass class]];
            fail(@"No exception thrown");
        }@catch(NSException *ex){
            
        }
    });
};

context(@"Mutliple registrations, first registration with class, options 0", ^{
    beforeEach(^{
        [masterChef registerClass:[CKInjectedClass class] withOptions:0];
    });
    
    validateMultipleRegistrations();
});

context(@"Mutliple registrations, first registration with class, options singleton", ^{
    beforeEach(^{
        [masterChef registerClass:[CKInjectedClass class] withOptions:CKObjectCookerRegisterClassOptionSingleton];
    });
    
    validateMultipleRegistrations();
});

context(@"Mutliple registrations, first registration with instance", ^{
    beforeEach(^{
        [masterChef registerInstance:[NSObject new] forClass:[CKInjectedClass class]];
    });
    
    validateMultipleRegistrations();
});

it(@"doesn't allow resolving of nil classes",^{
    @try{
        [masterChef resolve:nil];
        fail(@"No exception thrown");
    }@catch(NSException *ex){
        
    }
});

it(@"doesn't allow allocating nil classes",^{
    @try{
        [masterChef alloc:nil];
        fail(@"No exception thrown");
    }@catch(NSException *ex){
        
    }
});

it(@"injects the dependency",^{
    [masterChef registerClass:[CKClassToInject class] withOptions:0];
    CKInjectedClass *testObj = [[masterChef alloc:[CKInjectedClass class]] initWithInt:15];
    [[testObj.dependency should] beNonNil];
});

it(@"injects dependencies having a custom setter",^{
    [masterChef registerClass:[CKClassToInject class] withOptions:0];
    CKInjectedClass2 *testObj = [[masterChef alloc:[CKInjectedClass2 class]] init];
    [[testObj.customSetterDependency should] beNonNil];
});

it(@"injects the dependency from super class",^{
    [masterChef registerClass:[CKClassToInject class] withOptions:0];
    CKDerivedInjectedClass *testObj = [[masterChef alloc:[CKDerivedInjectedClass class]] initWithInt:15];
    [[testObj.dependency should] beNonNil];
});

it(@"injects the dependency with the correct type",^{
    [masterChef registerClass:[CKClassToInject class] withOptions:0];
    CKInjectedClass *testObj = [[masterChef alloc:[CKInjectedClass class]] initWithInt:15];
    [[theValue([testObj.dependency class]) should] equal:theValue([CKClassToInject class])];
});

it(@"doesn't inject properties that are not registered",^{
    [masterChef registerClass:[CKClassToInject class] withOptions:0];
    CKInjectedClass *testObj = [[masterChef alloc:[CKInjectedClass class]] initWithInt:15];
    [[testObj.dummy should] beNil];
});

it(@"allocates a new instance each time, for non-singleton",^{
    [masterChef registerClass:[CKClassToInject class] withOptions:0];
    CKInjectedClass *injectedObj1 = [[masterChef alloc:[CKInjectedClass class]] initWithInt:15];
    CKInjectedClass *injectedObj2 = [[masterChef alloc:[CKInjectedClass class]] initWithInt:16];
    [[injectedObj1.dependency shouldNot] equal:injectedObj2.dependency];
});

it(@"allocates only one instance for singleton", ^{
    [masterChef registerClass:[CKClassToInject class] withOptions:CKObjectCookerRegisterClassOptionSingleton];
    CKInjectedClass *injectedObj1 = [[masterChef alloc:[CKInjectedClass class]] initWithInt:15];
    CKInjectedClass *injectedObj2 = [[masterChef alloc:[CKInjectedClass class]] initWithInt:16];
    [[injectedObj1.dependency should] equal:injectedObj2.dependency];
});

it(@"serves the provided instance for dependency", ^{
    CKClassToInject *instance = [CKClassToInject new];
    [masterChef registerInstance:instance forClass:[CKClassToInject class]];
    CKInjectedClass *injectedObj = [[masterChef alloc:[CKInjectedClass class]] initWithInt:15];
    [[injectedObj.dependency should] equal:instance];
});

SPEC_END
