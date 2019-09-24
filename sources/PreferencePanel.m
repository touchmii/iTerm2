/*
 **  PreferencePanel.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: Implements the model and controller for the preference panel.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

/*
 * Preferences in iTerm2 are complicated, to say the least. Here is how the classes are organized.
 *
 * - PreferencePanel: There are two instances of this class: -sharedInstance and -sessionsInstance.
 *       The sharedInstance is the app settings panel, while sessionsInstance is for editing a
 *       single session (View>Edit Current Session).
 *     - GeneralPreferencesViewController:    View controller for Prefs>General
 *     - AppearancePreferencesViewController: View controller for Prefs>Appearance
 *     - KeysPreferencesViewController:       View controller for Prefs>Keys
 *     - PointerPreferencesViewController:    View controller for Prefs>Pointer
 *     - ProfilePreferencesViewController:    View controller for Prefs>Profiles
 *     - WindowArrangements:                  Owns Prefs>Arrangements
 *     - iTermAdvancedSettingsController:     Owns Prefs>Advanced
 *
 *  View controllers of tabs in PreferencePanel derive from iTermPreferencesBaseViewController.
 *  iTermPreferencesBaseViewController provides a map from NSControl* to PreferenceInfo.
 *  PreferenceInfo stores a pref's type, user defaults key, can constrain its value, and
 *  stores pointers to blocks that are run when a value is changed or a field needs to be updated
 *  for customizing how controls are bound to storage. Each view controller defines these bindings
 *  in its -awakeFromNib method.
 *
 *  User defaults are accessed through iTermPreferences, which assigns string constants to user
 *  defaults keys, defines default values for each key, and provides accessors. It also allows the
 *  exposed values to be computed from underlying values. (Currently, iTermPreferences is not used
 *  by advanced settings, but that should change).
 *
 *  Because per-profile preferences are similar, a parallel class structure exists for them.
 *  The following classes are view controllers for tabs in Prefs>Profiles:
 *
 *  - ProfilesGeneralPreferencesViewController
 *  - ProfilesColorPreferencesViewController
 *  - ProfilesTextPreferencesViewController
 *  - ProfilesWindowPreferencesViewController
 *  - ProfilesTerminalPreferencesViewController
 *  - ProfilesKeysPreferencesViewController
 *  - ProfilesAdvancedPreferencesViewController
 *
 *  These derive from iTermProfilePreferencesBaseViewController, which is just like
 *  iTermPreferencesBaseViewController, but its methods for accessing preference values take an
 *  additional profile: parameter. The analog of iTermPreferences is iTermProfilePreferences.
 *  */
#import "PreferencePanel.h"

#import "DebugLogging.h"
#import "AppearancePreferencesViewController.h"
#import "GeneralPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAdvancedSettingsViewController.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermKeyMappingViewController.h"
#import "iTermLaunchServices.h"
#import "iTermPreferences.h"
#import "iTermPreferencesSearch.h"
#import "iTermRemotePreferences.h"
#import "iTermPreferencesSearchEngineResultsWindowController.h"
#import "iTermSearchableViewController.h"
#import "iTermSizeRememberingView.h"
#import "iTermWarning.h"
#import "KeysPreferencesViewController.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSPopUpButton+iTerm.h"
#import "NSStringITerm.h"
#import "NSView+iTerm.h"
#import "PasteboardHistory.h"
#import "PointerPrefsController.h"
#import "ProfileModel.h"
#import "ProfilePreferencesViewController.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "SessionView.h"
#import "WindowArrangements.h"
#include <stdlib.h>

NSString *const kRefreshTerminalNotification = @"kRefreshTerminalNotification";
NSString *const kUpdateLabelsNotification = @"kUpdateLabelsNotification";
NSString *const kKeyBindingsChangedNotification = @"kKeyBindingsChangedNotification";
NSString *const kPreferencePanelDidUpdateProfileFields = @"kPreferencePanelDidUpdateProfileFields";
NSString *const kSessionProfileDidChange = @"kSessionProfileDidChange";
NSString *const kPreferencePanelDidLoadNotification = @"kPreferencePanelDidLoadNotification";
NSString *const kPreferencePanelWillCloseNotification = @"kPreferencePanelWillCloseNotification";

static NSString *const iTermPreferencePanelSearchFieldToolbarItemIdentifier = @"iTermPreferencePanelSearchFieldToolbarItemIdentifier";
static NSString *const iTermPrefsScrimMouseUpNotification = @"iTermPrefsScrimMouseUpNotification";

CGFloat iTermSharedPreferencePanelWindowMinimumWidth = 560;

// Strong references to the two preference panels.
static PreferencePanel *gSharedPreferencePanel;
static PreferencePanel *gSessionsPreferencePanel;

@interface iTermPrefsScrim : NSView
@property (nonatomic) NSView *cutoutView;
@end

@implementation iTermPrefsScrim {
    NSClickGestureRecognizer *_recognizer;
    BOOL savedPostNotifs;
    __weak NSClipView *_enclosingClipView;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        if (@available(macOS 10.14, *)) {} else {
            self.wantsLayer = YES;
        }
        _recognizer = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(click:)];
        [self addGestureRecognizer:_recognizer];
    }
    return self;
}

- (void)setCutoutView:(NSView *)cutoutView {
    _enclosingClipView.postsBoundsChangedNotifications = savedPostNotifs;
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    _cutoutView = cutoutView;

    NSView *temp = cutoutView;
    NSScrollView *outermostScrollview = nil;
    while (temp.enclosingScrollView) {
        outermostScrollview = temp.enclosingScrollView;
        temp = outermostScrollview;
    }
    _enclosingClipView = outermostScrollview.contentView;
    if (_enclosingClipView) {
        savedPostNotifs = _enclosingClipView.postsBoundsChangedNotifications;
        _enclosingClipView.postsBoundsChangedNotifications = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(scrollViewDidScroll:)
                                                     name:NSViewBoundsDidChangeNotification
                                                   object:_enclosingClipView];
    }
    [self setNeedsDisplay:YES];
}

- (void)scrollViewDidScroll:(NSNotification *)notification {
    [self setNeedsDisplay:YES];
}

- (BOOL)isOpaque {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    if (@available(macOS 10.14, *)) {
        [self mojaveDrawRect:dirtyRect];
        return;
    }
    [[NSColor clearColor] set];
    NSRectFill(dirtyRect);

    NSRect rect = [self convertRect:_cutoutView.bounds fromView:_cutoutView];
    rect = NSInsetRect(rect, -4, -4);
    [[NSColor redColor] set];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:4 yRadius:4];
    [path setLineWidth:4];
    [path stroke];
}

- (void)mojaveDrawRect:(NSRect)dirtyRect {
    const CGFloat baselineAlpha = 0.7;
    [[[NSColor blackColor] colorWithAlphaComponent:baselineAlpha] set];
    NSRectFill(dirtyRect);

    if (!_cutoutView) {
        return;
    }
    NSRect rect = [self convertRect:_cutoutView.bounds fromView:_cutoutView];

    const NSInteger steps = 30;
    const CGFloat stepSize = 0.5;
    const CGFloat highlightAlpha = 0.2;
    const CGFloat alphaStride = (baselineAlpha - highlightAlpha) / steps;
    CGFloat a = baselineAlpha - alphaStride;
    [[[NSColor blackColor] colorWithAlphaComponent:a] set];

    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositingOperationCopy];
    for (int i = 0; i < steps; i++) {
        const int r = (steps - i - 1);
        const CGFloat inset = stepSize * r;
        [[[NSColor blackColor] colorWithAlphaComponent:a] set];
        const NSRect insetRect = NSInsetRect(rect, -inset, -inset);
        const CGFloat radius = (inset + 1) * 2;
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:insetRect xRadius:radius yRadius:radius];
        [path fill];
        a -= alphaStride;
    }
}

- (void)click:(NSGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == NSGestureRecognizerStateRecognized) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermPrefsScrimMouseUpNotification object:nil];
    }
}

@end

@implementation iTermPrefsPanel

- (BOOL)setFrameUsingName:(NSWindowFrameAutosaveName)name {
    return [self setFrameUsingName:name force:NO];
}

- (NSString *)userDefaultsKeyForFrameName:(NSString *)name {
    return [NSString stringWithFormat:@"NoSyncFrame_%@", name];
}

- (BOOL)setFrameUsingName:(NSWindowFrameAutosaveName)name force:(BOOL)force {
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] objectForKey:[self userDefaultsKeyForFrameName:name]];
    return [self setFrameFromDict:dict];
}

- (void)saveFrameUsingName:(NSWindowFrameAutosaveName)name {
    [[NSUserDefaults standardUserDefaults] setObject:[self dictForFrame:self.frame onScreen:self.screen]
                                              forKey:[self userDefaultsKeyForFrameName:name]];
}

- (BOOL)haveSavedFrameForFrameWithName:(NSString *)name {
    return [[NSUserDefaults standardUserDefaults] objectForKey:[self userDefaultsKeyForFrameName:name]] != nil;
}

- (BOOL)setFrameFromDict:(NSDictionary *)dict {
    if (!dict[@"topLeft"] || !dict[@"screenFrame"]) {
        return NO;
    }
    const NSPoint topLeft = NSPointFromString(dict[@"topLeft"]);
    const NSRect screenFrame = NSRectFromString(dict[@"screenFrame"]);

    for (NSScreen *screen in [NSScreen screens]) {
        if (NSEqualRects(screen.frame, screenFrame)) {
            NSRect frame = self.frame;
            frame.origin.x = topLeft.x;
            frame.origin.y = topLeft.y - frame.size.height;
            [self setFrame:frame display:NO];
            return YES;
        }
    }
    return NO;
}

- (NSDictionary *)dictForFrame:(NSRect)frame onScreen:(NSScreen *)screen {
    const NSPoint topLeft = NSMakePoint(frame.origin.x,
                                        frame.origin.y + frame.size.height);
    return @{ @"topLeft": NSStringFromPoint(topLeft),
              @"screenFrame": NSStringFromRect(screen.frame) };
}

- (NSWindowPersistableFrameDescriptor)stringWithSavedFrame {
    return @"";
}

- (void)setFrameFromString:(NSWindowPersistableFrameDescriptor)string {
}

// Animated window changes call this a lot of times fast. Dumber than iOS, but occasionally comprehensible!
- (void)setFrame:(NSRect)frameRect display:(BOOL)flag {
    [super setFrame:frameRect display:flag];
    [self.prefsPanelDelegate prefsPanelDidChangeFrameTo:frameRect];
}

- (BOOL)makeFirstResponder:(NSResponder *)responder {
    BOOL result = [super makeFirstResponder:responder];
    if (result) {
        [self.prefsPanelDelegate responderWillBecomeFirstResponder:responder];
    }
    return result;
}

@end

@interface PreferencePanel() <iTermPrefsPanelDelegate, iTermPreferencesSearchEngineResultsWindowControllerDelegate, NSSearchFieldDelegate, NSTabViewDelegate>

@end

static iTermPreferencesSearchEngine *gSearchEngine;

@implementation PreferencePanel {
    ProfileModel *_profileModel;
    BOOL _editCurrentSessionMode;
    IBOutlet GeneralPreferencesViewController *_generalPreferencesViewController;
    IBOutlet AppearancePreferencesViewController *_appearancePreferencesViewController;
    IBOutlet KeysPreferencesViewController *_keysViewController;
    IBOutlet ProfilePreferencesViewController *_profilesViewController;
    IBOutlet PointerPreferencesViewController *_pointerViewController;
    IBOutlet iTermAdvancedSettingsViewController *_advancedViewController;

    IBOutlet NSToolbar *_toolbar;
    IBOutlet NSTabView *_tabView;
    IBOutlet NSToolbarItem *_globalToolbarItem;
    IBOutlet NSTabViewItem *_globalTabViewItem;
    IBOutlet NSToolbarItem *_appearanceToolbarItem;
    IBOutlet NSTabViewItem *_appearanceTabViewItem;
    IBOutlet NSToolbarItem *_keyboardToolbarItem;
    IBOutlet NSToolbarItem *_arrangementsToolbarItem;
    IBOutlet NSTabViewItem *_keyboardTabViewItem;
    IBOutlet NSTabViewItem *_arrangementsTabViewItem;
    IBOutlet NSToolbarItem *_bookmarksToolbarItem;
    IBOutlet NSTabViewItem *_bookmarksTabViewItem;
    IBOutlet NSToolbarItem *_mouseToolbarItem;
    IBOutlet NSTabViewItem *_mouseTabViewItem;
    IBOutlet NSToolbarItem *_advancedToolbarItem;
    IBOutlet NSTabViewItem *_advancedTabViewItem;
    IBOutlet NSToolbarItem *_flexibleSpaceToolbarItem;
    NSToolbarItem *_searchFieldToolbarItem;
    NSDictionary<NSString *, NSString *> *_keywords;
    NSDictionary<NSString *, id<iTermSearchableViewController>> *_keywordToViewController;
    // This class is not well named. It is a view controller for the window
    // arrangements tab. It's also a singleton :(
    IBOutlet WindowArrangements *arrangements_;
    NSSize _standardSize;
    NSInteger _disableResize;
    BOOL _tmux;
    NSTimeInterval _delay;

    iTermPrefsScrim *_scrim;
    iTermPreferencesSearchEngineResultsWindowController *_serpWindowController;
}

+ (instancetype)sharedInstance {
    if (!gSharedPreferencePanel) {
        gSharedPreferencePanel = [[PreferencePanel alloc] initWithProfileModel:[ProfileModel sharedInstance]
                                                        editCurrentSessionMode:NO];
    }
    return gSharedPreferencePanel;
}

+ (instancetype)sessionsInstance {
    if (!gSessionsPreferencePanel) {
        gSessionsPreferencePanel = [[PreferencePanel alloc] initWithProfileModel:[ProfileModel sessionsInstance]
                                                          editCurrentSessionMode:YES];
    }
    return gSessionsPreferencePanel;
}

- (BOOL)isSessionsInstance {
    return (self == [PreferencePanel sessionsInstance]);
}

- (instancetype)initWithProfileModel:(ProfileModel*)model
              editCurrentSessionMode:(BOOL)editCurrentSessionMode {
    self = [super initWithWindowNibName:@"PreferencePanel"];
    if (self) {
        _profileModel = model;

        [_toolbar setSelectedItemIdentifier:[_globalToolbarItem itemIdentifier]];

        _editCurrentSessionMode = editCurrentSessionMode;
    }
    return self;
}

- (BOOL)autoHidesHotKeyWindow {
    return NO;
}

#pragma mark - View layout

- (void)awakeFromNib {
    NSAssert(self.isWindowLoaded, @"window not loaded in %@", NSStringFromSelector(_cmd));
    [self.window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    [_toolbar setSelectedItemIdentifier:[_globalToolbarItem itemIdentifier]];

    _globalTabViewItem.view = _generalPreferencesViewController.view;
    _appearanceTabViewItem.view = _appearancePreferencesViewController.view;
    _keyboardTabViewItem.view = _keysViewController.view;
    _arrangementsTabViewItem.view = arrangements_.view;
    _mouseTabViewItem.view = _pointerViewController.view;
    _advancedTabViewItem.view = _advancedViewController.view;

    _generalPreferencesViewController.preferencePanel = self;
    _appearancePreferencesViewController.preferencePanel = self;
    _keysViewController.preferencePanel = self;
    _profilesViewController.preferencePanel = self;
    _profilesViewController.tmuxSession = _tmux;
    _pointerViewController.preferencePanel = self;

    if (_editCurrentSessionMode) {
        [self layoutSubviewsForEditCurrentSessionMode];
    } else {
        [self resizeWindowForTabViewItem:_globalTabViewItem animated:NO];
    }

    iTermPrefsPanel *panel = (iTermPrefsPanel *)self.window;
    panel.prefsPanelDelegate = self;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(scrimMouseUp:)
                                                 name:iTermPrefsScrimMouseUpNotification
                                               object:nil];
}

- (void)layoutSubviewsForEditCurrentSessionMode {
    [self selectProfilesTab];
    [_profilesViewController layoutSubviewsForEditCurrentSessionMode];
    [_toolbar setVisible:NO];

    [_profilesViewController resizeWindowForCurrentTabAnimated:NO];

}

#pragma mark - API

- (void)configureHotkeyForProfile:(Profile *)profile {
    _profilesViewController.scope = nil;
    [self window];
    [self selectProfilesTab];
    [self run];
    [_profilesViewController openToProfileWithGuidAndEditHotKey:profile[KEY_GUID]
                                                          scope:nil];
}

- (void)selectProfilesTab {
    // We want to disable resizing when opening sessionsInstace because it
    // would resize to be way too big (leaving space for the profiles list).
    // You can also get here because you want to open prefs directly to the
    // profile tab (such as when coming from the Profiles window).
    const BOOL shouldDisableResize = [self isSessionsInstance];
    if (shouldDisableResize) {
       _disableResize++;
    }
    [_tabView selectTabViewItem:_bookmarksTabViewItem];
    if (shouldDisableResize) {
        _disableResize--;
    }
    [_toolbar setSelectedItemIdentifier:[_bookmarksToolbarItem itemIdentifier]];
}

// NOTE: Callers should invoke makeKeyAndOrderFront if they are so inclined.
- (void)openToProfileWithGuid:(NSString*)guid
             selectGeneralTab:(BOOL)selectGeneralTab
                         tmux:(BOOL)tmux
                        scope:(iTermVariableScope<iTermSessionScope> *)scope {
    _tmux = tmux;
    _profilesViewController.tmuxSession = tmux;
    _profilesViewController.scope = scope;
    [self window];
    [self selectProfilesTab];
    [self run];
    [_profilesViewController openToProfileWithGuid:guid
                                  selectGeneralTab:selectGeneralTab
                                             scope:scope];
}

- (void)openToProfileWithGuid:(NSString *)guid
andEditComponentWithIdentifier:(NSString *)identifier
                         tmux:(BOOL)tmux
                        scope:(iTermVariableScope<iTermSessionScope> *)scope {
    _tmux = tmux;
    _profilesViewController.tmuxSession = tmux;
    _profilesViewController.scope = scope;
    [self window];
    [self selectProfilesTab];
    [self run];
    [_profilesViewController openToProfileWithGuid:guid
                    andEditComponentWithIdentifier:identifier
                                             scope:scope];
}

- (NSWindow *)window {
    BOOL shouldPostWindowLoadNotification = !self.windowLoaded;
    NSWindow *window = [super window];
    if (shouldPostWindowLoadNotification) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kPreferencePanelDidLoadNotification
                                                            object:self];
    }
    return window;
}

- (NSWindow *)windowIfLoaded {
    if (self.isWindowLoaded) {
        return self.window;
    } else {
        return nil;
    }
}

- (WindowArrangements *)arrangements {
    return arrangements_;
}

- (void)run {
    [NSApp activateIgnoringOtherApps:YES];
    [self window];
    [_generalPreferencesViewController updateEnabledState];
    [_profilesViewController selectFirstProfileIfNecessary];
    if (!self.window.isVisible) {
        [self showWindow:self];
    }
}

// Update the values in form fields to reflect the bookmark's state
- (void)underlyingBookmarkDidChange {
    [_profilesViewController refresh];
}

- (NSString *)nameForFrame {
    return [NSString stringWithFormat:@"%@Preferences", _profileModel.modelName];
}

#pragma mark - NSWindowController

- (void)windowWillLoad {
    DLog(@"Will load prefs panel from %@", [NSThread callStackSymbols]);
    // We finally set our autosave window frame name and restore the one from the user's defaults.
    [self setShouldCascadeWindows:NO];
}

- (void)windowDidLoad {
    // We shouldn't use setFrameAutosaveName: because this window controller controls two windows
    // with different frames (besides, I tried it and it doesn't work here for some reason).
    if (![(iTermPrefsPanel *)self.window haveSavedFrameForFrameWithName:self.nameForFrame]) {
        [self.window center];
    } else {
        [self.window setFrameUsingName:self.nameForFrame force:NO];
    }
}

#pragma mark - NSWindowDelegate

- (void)responderWillBecomeFirstResponder:(NSResponder *)responder {
    NSSearchField *searchField = (NSSearchField *)_searchFieldToolbarItem.view;
    if (responder == searchField && searchField.stringValue.length > 0) {
        [self showScrimAndSERP];
    } else {
        [self hideScrimAndSERP];
    }
}

- (void)windowDidMove:(NSNotification *)notification {
    [self.window saveFrameUsingName:self.nameForFrame];
}

- (void)windowWillClose:(NSNotification *)aNotification {
    [self.window saveFrameUsingName:self.nameForFrame];
    __typeof(self) strongSelf = self;
    if (self == gSharedPreferencePanel) {
        gSharedPreferencePanel = nil;
    } else if (self == gSessionsPreferencePanel) {
        gSessionsPreferencePanel = nil;
    }

    [strongSelf postWillCloseNotification];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kNonTerminalWindowBecameKeyNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (void)postWillCloseNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kPreferencePanelWillCloseNotification
                                                        object:self];
}

- (void)updateSERPOrigin {
    NSPoint point = [self.window convertPointToScreen:[_searchFieldToolbarItem.view convertPoint:NSMakePoint(0, NSHeight(_searchFieldToolbarItem.view.bounds))
                                                                                          toView:nil]];
    point.y -= 1;
    [_serpWindowController.window setFrameTopLeftPoint:point];
}

#pragma mark - Handle calls to current first responder

// Shell>Close
- (void)closeCurrentSession:(id)sender {
    [self close];
}

// Shell>Close Terminal Window
- (void)closeWindow:(id)sender {
    [self close];
}

- (void)close {
    [self postWillCloseNotification];
    [super close];
}

- (void)changeFont:(id)fontManager {
    [_profilesViewController changeFont:fontManager];
}

#pragma mark - IBActions

- (IBAction)showGlobalTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_globalTabViewItem];
}

- (IBAction)showAppearanceTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_appearanceTabViewItem];
}

- (IBAction)showBookmarksTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_bookmarksTabViewItem];
}

- (IBAction)showKeyboardTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_keyboardTabViewItem];
}

- (IBAction)showArrangementsTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_arrangementsTabViewItem];
}

- (IBAction)showMouseTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_mouseTabViewItem];
}

- (IBAction)showAdvancedTabView:(id)sender {
    [self hideScrimAndSERP];
    [_tabView selectTabViewItem:_advancedTabViewItem];
}

#pragma mark - NSToolbarDelegate and ToolbarItemValidation

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem {
    return TRUE;
}

- (NSArray *)orderedToolbarIdentifiers {
    if (!_globalToolbarItem) {
        return @[];
    }
    return @[ [_globalToolbarItem itemIdentifier],
              [_appearanceToolbarItem itemIdentifier],
              [_bookmarksToolbarItem itemIdentifier],
              [_keyboardToolbarItem itemIdentifier],
              [_arrangementsToolbarItem itemIdentifier],
              [_mouseToolbarItem itemIdentifier],
              [_advancedToolbarItem itemIdentifier],
              [_flexibleSpaceToolbarItem itemIdentifier],
              iTermPreferencePanelSearchFieldToolbarItemIdentifier];
}

- (void)createSearchField {
    _searchFieldToolbarItem = [[NSToolbarItem alloc] initWithItemIdentifier:iTermPreferencePanelSearchFieldToolbarItemIdentifier];

    NSSearchField *searchField = [[NSSearchField alloc] init];
    searchField.delegate = self;
    [searchField sizeToFit];

//    [_searchFieldToolbarItem setLabel:@"Search"];
    [_searchFieldToolbarItem setView:searchField];
}

- (NSDictionary *)toolbarIdentifierToItemDictionary {
    if (!_globalToolbarItem) {
        return @{};
    }
    if (!_searchFieldToolbarItem) {
        [self createSearchField];
    }
    return @{ [_globalToolbarItem itemIdentifier]: _globalToolbarItem,
              [_appearanceToolbarItem itemIdentifier]: _appearanceToolbarItem,
              [_bookmarksToolbarItem itemIdentifier]: _bookmarksToolbarItem,
              [_keyboardToolbarItem itemIdentifier]: _keyboardToolbarItem,
              [_arrangementsToolbarItem itemIdentifier]: _arrangementsToolbarItem,
              [_mouseToolbarItem itemIdentifier]: _mouseToolbarItem,
              [_advancedToolbarItem itemIdentifier]: _advancedToolbarItem,
              iTermPreferencePanelSearchFieldToolbarItemIdentifier: _searchFieldToolbarItem };
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {
    if (!flag) {
        return nil;
    }
    NSDictionary *theDict = [self toolbarIdentifierToItemDictionary];
    return theDict[itemIdentifier];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self orderedToolbarIdentifiers];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return [self orderedToolbarIdentifiers];
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar {
    return [self orderedToolbarIdentifiers];
}

#pragma mark - Hotkey Window

// This is used by iTermHotKeyController to not activate the hotkey while the field for typing
// the hotkey into is the first responder.
- (NSTextField*)hotkeyField {
    return _keysViewController.hotkeyField;
}

#pragma mark - Accessors

- (NSString *)currentProfileGuid {
    return [_profilesViewController selectedProfile][KEY_GUID];
}

#pragma mark - ProfilePreferencesViewControllerDelegate

- (ProfileModel *)profilePreferencesModel {
    return _profileModel;
}

#pragma mark - NSTabViewDelegate

- (NSToolbarItem *)toolbarItemForTabViewItem:(NSTabViewItem *)tabViewItem {
    if (tabViewItem == _globalTabViewItem) {
        return _globalToolbarItem;
    }
    if (tabViewItem == _appearanceTabViewItem) {
        return _appearanceToolbarItem;
    }
    if (tabViewItem == _keyboardTabViewItem) {
        return _keyboardToolbarItem;
    }
    if (tabViewItem == _arrangementsTabViewItem) {
        return _arrangementsToolbarItem;
    }
    if (tabViewItem == _bookmarksTabViewItem) {
        return _bookmarksToolbarItem;
    }
    if (tabViewItem == _mouseTabViewItem) {
        return _mouseToolbarItem;
    }
    if (tabViewItem == _advancedTabViewItem) {
        return _advancedToolbarItem;
    }
    return nil;
}

- (NSTabViewItem *)tabViewItemForViewController:(id)viewController {
    if (viewController == _generalPreferencesViewController) {
        return _globalTabViewItem;
    }
    if (viewController == _appearancePreferencesViewController) {
        return _appearanceTabViewItem;
    }
    if (viewController == _keysViewController) {
        return _keyboardTabViewItem;
    }
    if (viewController == arrangements_) {
        return _arrangementsTabViewItem;
    }
    if (viewController == _profilesViewController ||
        [_profilesViewController hasViewController:viewController]) {
        return _bookmarksTabViewItem;
    }
    if (viewController == _pointerViewController) {
        return _mouseTabViewItem;
    }
    if (viewController == _advancedViewController) {
        return _advancedTabViewItem;
    }
    return nil;
}

- (iTermPreferencesBaseViewController *)viewControllerForTabViewItem:(NSTabViewItem *)tabViewItem {
    if (tabViewItem == _globalTabViewItem) {
        return _generalPreferencesViewController;
    }
    if (tabViewItem == _appearanceTabViewItem) {
        return _appearancePreferencesViewController;
    }
    if (tabViewItem == _keyboardTabViewItem) {
        return _keysViewController;
    }
    if (tabViewItem == _arrangementsTabViewItem) {
        // TODO: the arrangements vc doesn't have the right superclass
        return nil;
    }
    if (tabViewItem == _bookmarksTabViewItem) {
        return _profilesViewController;
    }
    if (tabViewItem == _mouseTabViewItem) {
        return _pointerViewController;
    }
    if (tabViewItem == _advancedTabViewItem) {
        // TODO: the advanced vc doesn't have the right superclass
        return nil;
    }
    return nil;
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    if (tabViewItem == _bookmarksTabViewItem) {
        if (_disableResize == 0) {
            [_profilesViewController resizeWindowForCurrentTabAnimated:YES];
        }
        return;
    }

    [self resizeWindowForTabViewItem:tabViewItem animated:YES];
    [_profilesViewController invalidateSavedSize];
}

- (void)resizeWindowForTabViewItem:(NSTabViewItem *)tabViewItem animated:(BOOL)animated {
    iTermPreferencesBaseViewController *viewController = [self viewControllerForTabViewItem:tabViewItem];
    if (viewController.tabView != nil) {
        [viewController resizeWindowForCurrentTabAnimated:animated];
        return;
    }

    iTermSizeRememberingView *theView = (iTermSizeRememberingView *)tabViewItem.view;
    [theView resetToOriginalSize];
    NSRect rect = self.window.frame;
    NSPoint topLeft = rect.origin;
    topLeft.y += rect.size.height;
    NSSize size = [tabViewItem.view frame].size;
    rect.size = size;
    rect.size.height += 87;
    rect.size.width += 26;
    rect.origin = topLeft;
    rect.origin.y -= rect.size.height;
    rect.size.width = MAX(iTermSharedPreferencePanelWindowMinimumWidth, rect.size.width);
    [[self window] setFrame:rect display:YES animate:animated];
}

#pragma mark - NSSearchFieldDelegate

- (void)controlTextDidChange:(NSNotification *)obj {
    NSSearchField *searchField = (NSSearchField *)_searchFieldToolbarItem.view;
    if (searchField.stringValue.length == 0) {
        [self hideScrimAndSERP];
    } else {
        [self showScrimAndSERP];
    }
    _serpWindowController.documents = [self searchResults];
}

- (NSArray<id<iTermSearchableViewController>> *)searchableViewControllers {
    return @[_generalPreferencesViewController,
             _appearancePreferencesViewController,
             _keysViewController,
             _profilesViewController,
             _pointerViewController,
             _advancedViewController];
}

- (void)buildSearchEngineIfNeeded {
    if (gSearchEngine) {
        return;
    }
    gSearchEngine = [[iTermPreferencesSearchEngine alloc] init];

    for (id<iTermSearchableViewController> viewController in self.searchableViewControllers) {
        for (iTermPreferencesSearchDocument *doc in [viewController searchableViewControllerDocuments]) {
            [gSearchEngine addDocumentToIndex:doc];
        }
    }
}

- (NSArray<iTermPreferencesSearchDocument *> *)searchResults {
    [self buildSearchEngineIfNeeded];
    NSSearchField *searchField = (NSSearchField *)_searchFieldToolbarItem.view;
    return [gSearchEngine documentsMatchingQuery:searchField.stringValue];
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    [self hideScrimAndSERP];
}

- (void)controlTextDidBeginEditing:(NSNotification *)obj {
    [self showScrimAndSERP];
}

- (void)hideScrimAndSERP {
    [_serpWindowController close];
    _serpWindowController = nil;
    [_scrim removeFromSuperview];
    _scrim = nil;
}

- (void)showScrimAndSERP {
    [self showScrimIfNeeded];
    if (_serpWindowController) {
        return;
    }
    [_serpWindowController close];
    _serpWindowController = [[iTermPreferencesSearchEngineResultsWindowController alloc] initWithWindowNibName:@"iTermPreferencesSearchEngineResultsWindowController"];
    _serpWindowController.delegate = self;
    [self updateSERPOrigin];
    [self.window addChildWindow:_serpWindowController.window
                        ordered:NSWindowAbove];
    _serpWindowController.documents = [self searchResults];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(moveDown:)) {
        [_serpWindowController moveDown:nil];
        return YES;
    } else if (commandSelector == @selector(moveUp:)) {
        [_serpWindowController moveUp:nil];
        return YES;
    } else if (commandSelector == @selector(insertNewline:)) {
        [_serpWindowController insertNewline:nil];
        return YES;
    }
    return NO;
}

#pragma mark - iTermPrefsPanelDelegate

- (void)prefsPanelDidChangeFrameTo:(NSRect)newFrame {
    [self updateSERPOrigin];
    [_scrim setNeedsDisplay:YES];
}

#pragma mark - iTermPreferencesSearchEngineResultsWindowControllerDelegate

- (void)selectTabViewItem:(NSTabViewItem *)tabViewItem {
    [_tabView selectTabViewItem:tabViewItem];
    NSToolbarItem *item = [self toolbarItemForTabViewItem:tabViewItem];
    [_toolbar setSelectedItemIdentifier:item.itemIdentifier];
}

- (void)selectTabForViewController:(id<iTermSearchableViewController>)viewController {
    NSTabViewItem *tabViewItem = [self tabViewItemForViewController:viewController];
    if (tabViewItem) {
        [self selectTabViewItem:tabViewItem];
        return;
    }
    if ([viewController isKindOfClass:[iTermProfilePreferencesBaseViewController class]]) {
        [self selectTabViewItem:_bookmarksTabViewItem];
        if (_profilesViewController.selectedProfile == nil) {
            [_profilesViewController openToProfileWithGuid:[[ProfileModel sharedInstance] defaultBookmark][KEY_GUID]
                                          selectGeneralTab:NO
                                                     scope:nil];
        }
    }
}

- (id<iTermSearchableViewController>)viewControllerForDocumentOwnerIdentifier:(NSString *)ownerIdentifier {
    for (id<iTermSearchableViewController> vc in [self searchableViewControllers]) {
        if ([vc.documentOwnerIdentifier isEqualToString:ownerIdentifier]) {
            return vc;
        }
    }
    return [_profilesViewController viewControllerWithOwnerIdentifier:ownerIdentifier];
}

- (void)preferencesSearchEngineResultsDidSelectDocument:(iTermPreferencesSearchDocument *)document {
    _scrim.cutoutView = nil;
    id<iTermSearchableViewController> viewController = [self viewControllerForDocumentOwnerIdentifier:document.ownerIdentifier];
    if (!viewController) {
        return;
    }
    NSTabViewItem *tabViewItemBefore = _tabView.selectedTabViewItem;
    [self selectTabForViewController:viewController];
    const BOOL waitForTabToSwitch = (tabViewItemBefore != _tabView.selectedTabViewItem);
    BOOL waitForInnerTabToSwitch = NO;
    NSSearchField *searchField = (NSSearchField *)_searchFieldToolbarItem.view;
    _scrim.cutoutView = [viewController searchableViewControllerRevealItemForDocument:document
                                                                             forQuery:searchField.stringValue
                                                                        willChangeTab:&waitForInnerTabToSwitch];
    CGFloat delay = 1;
    if (waitForTabToSwitch || (!waitForTabToSwitch && waitForInnerTabToSwitch)) {
        delay = 2;
    }
    _delay = delay;
}

- (NSTabViewItem *)innerTabViewItem {
    return [self viewControllerForTabViewItem:_tabView.selectedTabViewItem].tabView.selectedTabViewItem;
}

- (void)preferencesSearchEngineResultsDidActivateDocument:(iTermPreferencesSearchDocument *)document {
    NSView *scrim = _scrim;
    self->_scrim = nil;
    [self.window makeFirstResponder:nil];
    [NSView animateWithDuration:0.5
                          delay:_delay
                     animations:^{
                         scrim.animator.alphaValue = 0;
                     }
                     completion:^(BOOL finished) {
                         [scrim removeFromSuperview];
                     }];
    return;
}

#pragma mark - Scrim

- (void)showScrimIfNeeded {
    if (_scrim) {
        return;
    }
    _scrim = [[iTermPrefsScrim alloc] init];
    _scrim.frame = self.window.contentView.bounds;
    _scrim.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.window.contentView addSubview:_scrim];
}

- (void)scrimMouseUp:(NSNotification *)notification {
    [self.window makeFirstResponder:nil];
}

@end
