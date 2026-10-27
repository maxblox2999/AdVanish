#import "ASPAppListController.h"

@implementation ASPAppListController

- (NSString *)bid {
    return [self.specifier propertyForKey:@"bid"] ?: @"";
}

// Per-app key: "<bundleID>-<Suffix>".
- (NSString *)k:(NSString *)suffix {
    return [NSString stringWithFormat:@"%@-%@", [self bid], suffix];
}

// Grey out (make non-interactive) a specifier when the condition holds.
- (PSSpecifier *)disable:(PSSpecifier *)s when:(BOOL)cond {
    if (cond) [s setProperty:@NO forKey:@"enabled"];
    return s;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        NSString *enableKey = [@"enabled-" stringByAppendingString:[self bid]];
        BOOL enabled  = [self boolPref:enableKey default:NO];
        BOOL speedOn  = [self boolPref:[self k:@"SpeedUpVideo"] default:YES];

        [specs addObject:[self groupNamed:nil
                                   footer:@"Settings for this app only. They apply next time the app is launched."]];
        [specs addObject:[self switchSpecifierNamed:@"Enabled" key:enableKey default:NO]];
        [specs addObject:[self groupNamed:@"Ad playback"
                                   footer:@"16x playback for supported ads. The button uses the same speed system. "
                                          @"Rewards still require the SDK's completion and validation."]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Show fast-forward button" key:[self k:@"ManualSkip"] default:YES] when:!enabled]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Bypass ads jailbreak detection" key:[self k:@"BypassJailbreak"] default:YES] when:!enabled]];

        [specs addObject:[self groupNamed:@"Fast-forward ads"
                                   footer:!enabled ? @"Enable this app first."
                                   : @"Automatic video acceleration. Force inline can break ads. "
                                     @"Include native video also speeds in-game cutscenes."]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Fast-forward ads" key:[self k:@"SpeedUpVideo"] default:YES] when:!enabled]];
        if (speedOn) {
            [specs addObject:[self disable:[self subSwitchNamed:@"Force inline video" key:[self k:@"ForceInline"] default:NO] when:!enabled]];
            [specs addObject:[self disable:[self subSwitchNamed:@"Include native video" key:[self k:@"SpeedNativeVideo"] default:NO] when:!enabled]];
        }

        // Independent of Fast-forward: speeds the countdown even when the video can't be sped.
        [specs addObject:[self groupNamed:@"Ad countdowns"
                                   footer:@"Speeds timers and gameplay clocks inside a detected ad. "
                                          @"SDK and server timers can remain unchanged."]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Rush web countdowns" key:[self k:@"CompressTimers"] default:YES] when:!enabled]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Accelerate gameplay clock" key:[self k:@"AccelerateClock"] default:YES] when:!enabled]];

        [specs addObject:[self groupNamed:@"Completion"
                                   footer:@"Supported playable controls can receive generated input. Unknown games "
                                          @"and controls that require a real touch still need interaction. "
                                          @"Auto-close waits for a genuine SDK completion signal."]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Assist supported playables" key:[self k:@"AutoInteract"] default:YES] when:!enabled]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Close completed ads" key:[self k:@"AutoDismiss"] default:YES] when:!enabled]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Block ad redirects" key:[self k:@"BlockRedirects"] default:YES] when:!enabled]];

        _specifiers = [specs copy];
    }
    return _specifiers;
}

// Rebuild dependent rows after a switch changes.
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    NSString *changed = [specifier propertyForKey:@"key"];
    if ([changed isEqualToString:[@"enabled-" stringByAppendingString:[self bid]]] ||
        [changed isEqualToString:[self k:@"ManualSkip"]] ||
        [changed isEqualToString:[self k:@"SpeedUpVideo"]] ||
        [changed isEqualToString:[self k:@"CompressTimers"]]) {
        _specifiers = nil;
        [self reloadSpecifiers];
    }
}

@end
