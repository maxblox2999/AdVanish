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
        BOOL manual = [self boolPref:[self k:@"ManualSkip"] default:YES];
        BOOL speedOn  = [self boolPref:[self k:@"SpeedUpVideo"] default:YES];
        BOOL timersOn = [self boolPref:[self k:@"CompressTimers"] default:NO];
        BOOL speedOff = !enabled || manual;

        [specs addObject:[self groupNamed:nil
                                   footer:@"Settings for this app only. They apply next time the app is launched."]];
        [specs addObject:[self switchSpecifierNamed:@"Enabled" key:enableKey default:NO]];
        [specs addObject:[self groupNamed:@"Manual skipping"
                                   footer:@"Shows a Fast-forward ad button. Pressing requests 2x video playback "
                                          @"without jumping to the end. SDK countdowns stay unchanged. "
                                          @"Wait for the app's reward or countdown and use its own Close button."]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Show skip button" key:[self k:@"ManualSkip"] default:YES] when:!enabled]];
        [specs addObject:[self groupNamed:@"Legacy blocking"
                                   footer:@"Uses the older SDK list and can prevent rewarded ads from loading. "
                                          @"Turn off the skip button to use legacy blocking or acceleration."]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Block ads by SDK" key:[self k:@"BlockAds"] default:NO] when:speedOff]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Bypass ads jailbreak detection" key:[self k:@"BypassJailbreak"] default:YES] when:!enabled]];

        [specs addObject:[self groupNamed:@"Fast-forward ads"
                                   footer:!enabled ? @"Enable this app first."
                                   : manual ? @"Automatic acceleration is off while the manual skip button is enabled."
                                   : @"Accelerates video automatically. “Force inline video” helps "
                                     @"stuck fullscreen video but can break some ads (e.g. AppLovin) — leave it off "
                                     @"unless a video won't speed up. “Include native video” also speeds in-game cutscenes."]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Fast-forward ads" key:[self k:@"SpeedUpVideo"] default:YES] when:speedOff]];
        if (speedOn) {
            [specs addObject:[self disable:[self subSwitchNamed:@"Force inline video" key:[self k:@"ForceInline"] default:NO] when:speedOff]];
            [specs addObject:[self disable:[self subSwitchNamed:@"Include native video" key:[self k:@"SpeedNativeVideo"] default:NO] when:speedOff]];
        }

        // Independent of Fast-forward: speeds the countdown even when the video can't be sped.
        [specs addObject:[self groupNamed:@"Ad countdowns"
                                   footer:@"Speeds the countdown to the close/reward — works on its own, without "
                                          @"video fast-forward. For timer-gated playables, or video ads whose "
                                          @"picture won't speed up. “Accelerate clock” also speeds wall-clock "
                                          @"timers. It pauses while a video is on screen to avoid freezing it."]];
        [specs addObject:[self disable:[self switchSpecifierNamed:@"Rush web countdowns" key:[self k:@"CompressTimers"] default:NO] when:speedOff]];
        if (timersOn) {
            [specs addObject:[self disable:[self subSwitchNamed:@"Accelerate clock" key:[self k:@"AccelerateClock"] default:NO] when:speedOff]];
        }

        [specs addObject:[self groupNamed:@"Speed"
                                   footer:@"How many times faster (default 8). If a reward stops counting, "
                                          @"lower it to 3–4 — high speeds can skip the ad's completion event."]];
        [specs addObject:[self disable:[self numberFieldNamed:@"Multiplier" key:[self k:@"VideoRate"] default:@(8)] when:speedOff]];

        _specifiers = [specs copy];
    }
    return _specifiers;
}

// Rebuild when Enabled / Block / Fast-forward / Rush toggle (to grey-out or reveal rows).
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    NSString *changed = [specifier propertyForKey:@"key"];
    if ([changed isEqualToString:[@"enabled-" stringByAppendingString:[self bid]]] ||
        [changed isEqualToString:[self k:@"BlockAds"]] ||
        [changed isEqualToString:[self k:@"ManualSkip"]] ||
        [changed isEqualToString:[self k:@"SpeedUpVideo"]] ||
        [changed isEqualToString:[self k:@"CompressTimers"]]) {
        _specifiers = nil;
        [self reloadSpecifiers];
    }
}

@end
