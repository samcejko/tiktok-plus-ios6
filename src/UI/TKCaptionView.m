#import "TKCaptionView.h"
#import <CoreText/CoreText.h>
#import "TKUtils.h"
#import "TKCommon.h"

static NSString * const TKLinkAttribute = @"TKLink";
static const CGFloat TKLineGap = 1;
static const CGFloat TKTapSlop = 8;      // a finger is wider than a letter

static BOOL TKRangeTaken(NSRange r, NSArray *taken)
{
    for (NSValue *v in taken) if (NSIntersectionRange(r, v.rangeValue).length) return YES;
    return NO;
}

@interface TKCaptionView ()
@property (nonatomic, strong) NSAttributedString *attributed;
@property (nonatomic, strong) NSArray *lines;       // CTLineRef
@property (nonatomic, strong) NSArray *tops;        // NSNumber: each line's top
@property (nonatomic, strong) NSArray *ascents;
@property (nonatomic) CGFloat builtWidth;           // the width the lines were broken for (-1: none)
@property (nonatomic) CGFloat builtHeight;
@end

@implementation TKCaptionView

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.contentMode = UIViewContentModeRedraw;
        self.userInteractionEnabled = NO;
        _font = [UIFont systemFontOfSize:14];
        _maxLines = 3;
        _builtWidth = -1;
    }
    return self;
}

- (void)setText:(NSString *)text
{
    if ((text == _text) || [text isEqualToString:_text]) return;
    _text = [text copy];
    [self rebuildText];
}

- (void)setFont:(UIFont *)font { _font = font; [self rebuildText]; }
- (void)setMaxLines:(NSUInteger)maxLines { _maxLines = maxLines; self.builtWidth = -1; [self setNeedsDisplay]; }

// The text with CoreText attributes: web links, hashtags and mentions bold and marked with what they open
- (void)rebuildText
{
    NSString *s = self.text ?: @"";
    UIFont *bold = [UIFont boldSystemFontOfSize:self.font.pointSize];
    CTFontRef plainFont = CTFontCreateWithName((__bridge CFStringRef)self.font.fontName, self.font.pointSize, NULL);
    CTFontRef boldFont = CTFontCreateWithName((__bridge CFStringRef)bold.fontName, bold.pointSize, NULL);
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:s attributes:@{
        (id)kCTFontAttributeName: (__bridge id)plainFont,
        (id)kCTForegroundColorAttributeName: (__bridge id)[UIColor whiteColor].CGColor }];
    // web links first: a #hashtag or @mention inside one ("youtube.com/@name") belongs to the link (the domain-like
    // tail of a mention, "@john.name", is no link: TKUtils leaves it out)
    NSMutableArray *taken = [NSMutableArray array];
    for (NSTextCheckingResult *m in [TKUtils webLinksInText:s]) {
        [a addAttributes:@{ (id)kCTFontAttributeName: (__bridge id)boldFont, TKLinkAttribute: [@"url:" stringByAppendingString:m.URL.absoluteString] } range:m.range];
        [taken addObject:[NSValue valueWithRange:m.range]];
    }
    static NSRegularExpression *tags, *users;
    if (!tags) tags = [NSRegularExpression regularExpressionWithPattern:@"#[\\p{L}\\p{N}_]+" options:0 error:NULL];
    if (!users) users = [NSRegularExpression regularExpressionWithPattern:@"(?<![\\w.])@[A-Za-z0-9_.]*[A-Za-z0-9_]" options:0 error:NULL];
    for (NSTextCheckingResult *m in [tags matchesInString:s options:0 range:NSMakeRange(0, s.length)]) {
        if (TKRangeTaken(m.range, taken)) continue;
        NSString *name = [s substringWithRange:NSMakeRange(m.range.location + 1, m.range.length - 1)];
        [a addAttributes:@{ (id)kCTFontAttributeName: (__bridge id)boldFont, TKLinkAttribute: [@"tag:" stringByAppendingString:name] } range:m.range];
    }
    for (NSTextCheckingResult *m in [users matchesInString:s options:0 range:NSMakeRange(0, s.length)]) {
        if (TKRangeTaken(m.range, taken)) continue;
        NSString *handle = [s substringWithRange:NSMakeRange(m.range.location + 1, m.range.length - 1)];
        if (handle.length < 2) continue;
        [a addAttributes:@{ (id)kCTFontAttributeName: (__bridge id)boldFont, TKLinkAttribute: [@"user:" stringByAppendingString:handle] } range:m.range];
    }
    CFRelease(plainFont);
    CFRelease(boldFont);
    self.attributed = a;
    self.builtWidth = -1;
    [self setNeedsDisplay];
}

// Breaks the text into lines for a width; the last allowed line takes the rest of the text, cut with "…"
- (void)buildForWidth:(CGFloat)width
{
    if (width == self.builtWidth) return;
    self.builtWidth = width;
    NSMutableArray *lines = [NSMutableArray array], *tops = [NSMutableArray array], *ascents = [NSMutableArray array];
    CGFloat y = 0;
    NSAttributedString *a = self.attributed;
    if (a.length && width > 10) {
        CTTypesetterRef setter = CTTypesetterCreateWithAttributedString((__bridge CFAttributedStringRef)a);
        CFIndex start = 0, length = (CFIndex)a.length;
        while (start < length) {
            CFIndex count = CTTypesetterSuggestLineBreak(setter, start, width);
            if (count <= 0) break;
            BOOL cut = self.maxLines && lines.count + 1 == self.maxLines && start + count < length;
            CTLineRef line;
            if (cut) {
                CTLineRef rest = CTTypesetterCreateLine(setter, CFRangeMake(start, length - start));
                NSDictionary *tokenAttrs = [a attributesAtIndex:(NSUInteger)start effectiveRange:NULL];
                CTLineRef dots = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)[[NSAttributedString alloc] initWithString:@"…" attributes:tokenAttrs]);
                line = CTLineCreateTruncatedLine(rest, width, kCTLineTruncationEnd, dots);
                CFRelease(rest);
                CFRelease(dots);
                if (!line) line = CTTypesetterCreateLine(setter, CFRangeMake(start, count));
            } else {
                line = CTTypesetterCreateLine(setter, CFRangeMake(start, count));
            }
            CGFloat ascent = 0, descent = 0, leading = 0;
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
            [lines addObject:(__bridge_transfer id)line];
            [tops addObject:@(y)];
            [ascents addObject:@(ascent)];
            y += ceilf(ascent + descent + leading) + TKLineGap;
            start += count;
            if (cut) break;
        }
        CFRelease(setter);
    }
    self.lines = lines;
    self.tops = tops;
    self.ascents = ascents;
    self.builtHeight = lines.count ? y - TKLineGap : 0;
}

- (CGSize)sizeThatFits:(CGSize)size
{
    [self buildForWidth:floorf(size.width)];
    return CGSizeMake(size.width, ceilf(self.builtHeight));
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    if (floorf(self.bounds.size.width) != self.builtWidth) [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    [self buildForWidth:floorf(self.bounds.size.width)];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 2, [UIColor colorWithWhite:0 alpha:0.7].CGColor);
    CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    CGContextTranslateCTM(ctx, 0, self.bounds.size.height);
    CGContextScaleCTM(ctx, 1, -1);
    for (NSUInteger i = 0; i < self.lines.count; i++) {
        CGFloat baseline = self.bounds.size.height - ([self.tops[i] floatValue] + [self.ascents[i] floatValue]);
        CGContextSetTextPosition(ctx, 0, baseline);
        CTLineDraw((__bridge CTLineRef)self.lines[i], ctx);
    }
    CGContextRestoreGState(ctx);
}

- (NSString *)linkAtPoint:(CGPoint)p
{
    [self buildForWidth:floorf(self.bounds.size.width)];
    for (NSUInteger i = 0; i < self.lines.count; i++) {
        CTLineRef line = (__bridge CTLineRef)self.lines[i];
        CGFloat top = [self.tops[i] floatValue];
        CGFloat bottom = (i + 1 < self.tops.count) ? [self.tops[i + 1] floatValue] : self.builtHeight;
        if (p.y < top - TKTapSlop || p.y > bottom + TKTapSlop) continue;
        CFIndex at = CTLineGetStringIndexForPosition(line, CGPointMake(p.x, 0));
        CFRange span = CTLineGetStringRange(line);
        for (CFIndex k = at - 1; k <= at; k++) {
            if (k < span.location || k >= span.location + span.length || k >= (CFIndex)self.attributed.length) continue;
            NSRange r;
            NSString *link = [self.attributed attribute:TKLinkAttribute atIndex:(NSUInteger)k effectiveRange:&r];
            if (!link) continue;
            CGFloat x0 = CTLineGetOffsetForStringIndex(line, (CFIndex)r.location, NULL);
            CGFloat x1 = CTLineGetOffsetForStringIndex(line, (CFIndex)NSMaxRange(r), NULL);
            if (p.x >= MIN(x0, x1) - TKTapSlop && p.x <= MAX(x0, x1) + TKTapSlop) return link;
        }
    }
    return nil;
}

@end
