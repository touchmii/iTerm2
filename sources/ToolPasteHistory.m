//
//  ToolPasteHistory.m
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//

#import "ToolPasteHistory.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermCompetentTableRowView.h"
#import "iTermController.h"
#import "iTermSecureKeyboardEntryController.h"
#import "iTermToolWrapper.h"
#import "NSDateFormatterExtras.h"
#import "NSTableColumn+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PseudoTerminal.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 4;

@implementation ToolPasteHistory {
    NSScrollView *scrollView_;
    NSTableView *tableView_;
    NSButton *clear_;
    NSTextField *_secureKeyboardEntryWarning;
    PasteboardHistory *pasteHistory_;
    NSTimer *minuteRefreshTimer_;
    BOOL shutdown_;
    NSMutableParagraphStyle *_paragraphStyle;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        _paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
        _paragraphStyle.allowsDefaultTighteningForTruncation = NO;

        clear_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
        [clear_ setButtonType:NSMomentaryPushInButton];
        [clear_ setTitle:@"Clear All"];
        [clear_ setTarget:self];
        [clear_ setAction:@selector(clear:)];
        [clear_ setBezelStyle:NSSmallSquareBezelStyle];
        [clear_ sizeToFit];
        [clear_ setAutoresizingMask:NSViewMinYMargin];
        [self addSubview:clear_];

        _secureKeyboardEntryWarning = [NSTextField newLabelStyledTextField];
        _secureKeyboardEntryWarning.stringValue = @"⚠️ Secure keyboard entry disables paste history.";
        _secureKeyboardEntryWarning.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        _secureKeyboardEntryWarning.cell.truncatesLastVisibleLine = YES;
        _secureKeyboardEntryWarning.hidden = ![[iTermSecureKeyboardEntryController sharedInstance] isEnabled];
        [self addSubview:_secureKeyboardEntryWarning];
        [_secureKeyboardEntryWarning sizeToFit];
        _secureKeyboardEntryWarning.frame = NSMakeRect(0, 0, frame.size.width, _secureKeyboardEntryWarning.frame.size.height);

        scrollView_ = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - kButtonHeight - kMargin)];
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
        [scrollView_ setBorderType:NSBezelBorder];
        NSSize contentSize = [scrollView_ contentSize];
        [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        if (@available(macOS 10.14, *)) { } else {
            scrollView_.drawsBackground = NO;
        }
        
        tableView_ = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"contents"];
        [col setEditable:NO];
        [tableView_ addTableColumn:col];
        [[col headerCell] setStringValue:@"Values"];
        [tableView_ setHeaderView:nil];
        [tableView_ setDataSource:self];
        [tableView_ setDelegate:self];
        tableView_.intercellSpacing = NSMakeSize(tableView_.intercellSpacing.width, 0);
        tableView_.rowHeight = 15;

        [tableView_ setDoubleAction:@selector(doubleClickOnTableView:)];
        [tableView_ setAutoresizingMask:NSViewWidthSizable];

        [scrollView_ setDocumentView:tableView_];
        [self addSubview:scrollView_];

        [tableView_ sizeToFit];
        [tableView_ setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];

        pasteHistory_ = [PasteboardHistory sharedInstance];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pasteboardHistoryDidChange:)
                                                     name:kPasteboardHistoryDidChange
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(secureKeyboardEntryDidChange:)
                                                     name:iTermDidToggleSecureInputNotification
                                                   object:nil];
        minuteRefreshTimer_ = [NSTimer scheduledTimerWithTimeInterval:61
                                                               target:self
                                                             selector:@selector(pasteboardHistoryDidChange:)
                                                             userInfo:nil
                                                              repeats:YES];
        [tableView_ performSelector:@selector(scrollToEndOfDocument:) withObject:nil afterDelay:0];
        [tableView_ reloadData];
    }
    return self;
}

- (void)dealloc {
    [minuteRefreshTimer_ invalidate];
}

- (void)shutdown {
    shutdown_ = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [minuteRefreshTimer_ invalidate];
    minuteRefreshTimer_ = nil;
}

- (NSSize)contentSize {
    NSSize size = [scrollView_ contentSize];
    size.height = [[tableView_ headerView] frame].size.height;
    size.height += [tableView_ numberOfRows] * ([tableView_ rowHeight] + [tableView_ intercellSpacing].height);
    return size;
}

- (void)relayout {
    NSRect frame = self.frame;
    [clear_ sizeToFit];
    [clear_ setFrame:NSMakeRect(frame.size.width - clear_.frame.size.width, frame.size.height - kButtonHeight, clear_.frame.size.width, kButtonHeight)];

    _secureKeyboardEntryWarning.hidden = [iTermAdvancedSettingsModel saveToPasteHistoryWhenSecureInputEnabled] || ![[iTermSecureKeyboardEntryController sharedInstance] isEnabled];
    _secureKeyboardEntryWarning.frame = NSMakeRect(0, 0, frame.size.width, _secureKeyboardEntryWarning.frame.size.height);

    const CGFloat offset = _secureKeyboardEntryWarning.isHidden ? 0 : _secureKeyboardEntryWarning.frame.size.height + 4;
    [scrollView_ setFrame:NSMakeRect(0, offset, frame.size.width, frame.size.height - kButtonHeight - kMargin - offset)];

    NSSize contentSize = [self contentSize];
    [tableView_ setFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
}

- (BOOL)isFlipped {
    return YES;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    return [[iTermCompetentTableRowView alloc] initWithFrame:NSZeroRect];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return pasteHistory_.entries.count;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    static NSString *const identifier = @"ToolPasteHistoryEntry";
    NSTextField *result = [tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
    }

    NSAttributedString *value = [self attributedStringForTableColumn:tableColumn row:row];
    result.attributedStringValue = value;

    return result;
}

- (NSAttributedString *)attributedStringForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    return [[NSAttributedString alloc] initWithString:[self stringForTableColumn:aTableColumn row:rowIndex]
                                           attributes:@{NSFontAttributeName: [NSFont fontWithName:@"Menlo" size:11],
                                                        NSParagraphStyleAttributeName: _paragraphStyle }];
}

- (NSString *)stringForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    PasteboardEntry* entry = pasteHistory_.entries[rowIndex];
    if ([[aTableColumn identifier] isEqualToString:@"date"]) {
        // Date
        return [NSDateFormatter compactDateDifferenceStringFromDate:entry.timestamp];
    } else {
        // Contents
        NSString* value = [[entry mainValue] stringByReplacingOccurrencesOfString:@"\n"
                                                                       withString:@" "];
        // Don't return an insanely long value to avoid performance issues.
        const NSUInteger kMaxLength = 256;
        if (value.length > kMaxLength) {
            return [value substringToIndex:kMaxLength];
        } else {
            return value;
        }
    }
}

- (void)secureKeyboardEntryDidChange:(NSNotification *)notification {
    [self relayout];
}

- (void)pasteboardHistoryDidChange:(id)sender {
    [self update];
}

- (void)update {
    [tableView_ reloadData];
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];

    NSResponder *firstResponder = [[tableView_ window] firstResponder];
    if (firstResponder != tableView_) {
        [tableView_ scrollToEndOfDocument:nil];
    }
}

- (void)fixCursor {
    if (shutdown_) {
        return;
    }
    iTermToolWrapper *wrapper = self.toolWrapper;
    [wrapper.delegate.delegate toolbeltUpdateMouseCursor];
}

- (void)doubleClickOnTableView:(id)sender {
    NSInteger selectedIndex = [tableView_ selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    PasteboardEntry* entry = pasteHistory_.entries[selectedIndex];
    NSPasteboard* thePasteboard = [NSPasteboard generalPasteboard];
    [thePasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [thePasteboard setString:[entry mainValue] forType:NSStringPboardType];
    PTYTextView *textView = [[iTermController sharedInstance] frontTextView];
    [textView paste:nil];
    [textView.window makeFirstResponder:textView];
}

- (void)clear:(id)sender {
    [pasteHistory_ eraseHistory];
    [pasteHistory_ clear];
    [tableView_ reloadData];
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];
}

- (CGFloat)minimumHeight {
    return 60;
}

@end
