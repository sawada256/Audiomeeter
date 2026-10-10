#import <Cocoa/Cocoa.h>
extern "C" void vm_juce_hide_editor(void*);
@interface VMEditorActions : NSObject
@property(nonatomic,assign) void* plugin;
-(void)hideEditor:(id)sender;
@end
@implementation VMEditorActions
-(void)hideEditor:(id)sender { (void)sender; if(self.plugin)vm_juce_hide_editor(self.plugin); }
@end
static VMEditorActions* actions=nil;
// Force Touch's second stage must not steal a normal click from a plugin control.
static void configureClick(NSView* view, NSPressureConfiguration* configuration) {
    view.pressureConfiguration = configuration;
    for (NSView* child in view.subviews) configureClick(child, configuration);
}
extern "C" void vm_release_editor_commands(void* plugin) {
    if(actions.plugin==plugin)actions.plugin=nullptr;
}
extern "C" void vm_configure_editor_clicks(void* nativeView,void* plugin) {
    NSView* view = (NSView*)nativeView;
    if (![view isKindOfClass:[NSView class]]) return;
    if(!actions) actions=[[VMEditorActions alloc] init];
    actions.plugin=plugin;
    NSMenu* menu=[[[NSMenu alloc] initWithTitle:@""] autorelease];
    NSMenuItem* root=[[[NSMenuItem alloc] initWithTitle:@"Audiomeeter Plugin" action:nil keyEquivalent:@""] autorelease];
    NSMenu* submenu=[[[NSMenu alloc] initWithTitle:@"Audiomeeter Plugin"] autorelease];
    const char* language=getenv("AUDIOMEETER_LANGUAGE");
    NSString* closeTitle=(language && strcmp(language,"en")==0) ? @"Close (Hide)" : @"閉じる（非表示）";
    for(NSString* key in @[@"w",@"q"]) {
        NSMenuItem* hide=[[[NSMenuItem alloc] initWithTitle:closeTitle action:@selector(hideEditor:) keyEquivalent:key] autorelease];
        hide.target=actions; [submenu addItem:hide];
    }
    root.submenu=submenu;[menu addItem:root];NSApp.mainMenu=menu;
    NSPressureConfiguration* configuration = [[[NSPressureConfiguration alloc] initWithPressureBehavior:NSPressureBehaviorPrimaryClick] autorelease];
    configureClick(view, configuration);
    NSWindow* window = view.window;
    window.styleMask |= NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskTitled;
    [window standardWindowButton:NSWindowCloseButton].hidden=NO;
    window.ignoresMouseEvents = NO;
    window.acceptsMouseMovedEvents = YES;
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    if (window.miniaturized) [window deminiaturize:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
}

extern "C" void vm_return_focus_to_parent(int pid) {
    {
        NSRunningApplication* parent=[NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        [parent activateWithOptions:0];
    }
}
