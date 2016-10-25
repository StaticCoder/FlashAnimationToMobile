/*
 copyright 2016 wanghongyu.
 The project page：https://github.com/hardman/FlashAnimationToMobile
 My blog page: http://blog.csdn.net/hard_man/
 */

#import "FlashViewNode.h"
#import "FlashViewTool.h"

@implementation FlashViewBaseNode
-(void) updateToIndex:(NSInteger)index{}
-(void) trigerEventWithIndex:(NSInteger)index delegate:(id<FlashViewDelegate>)delegate{}
-(void) onReady{}
-(void) onClean{}

-(void)dealloc{
    [self onClean];
}
@end

//帧数据
@implementation FlashViewFrameNode
@end

//层数据
@interface FlashViewLayerNode()
@property (nonatomic, strong) CALayer *layer;
@property (nonatomic, strong) CALayer *colorLayer;
@property (nonatomic, strong) CALayer *maskLayer;
@property (nonatomic, strong) NSMutableArray<FlashViewFrameNode *> *keyFrames;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, FlashViewFrameNode *> *frameDict;
@end

@implementation FlashViewLayerNode

//计算出每一帧的数据(位置，大小等信息)
-(void) onReady{
    [self createFrameDict];
}

//移除所有layer和数据
-(void) onClean{
    [_layer removeFromSuperlayer];
    _layer = nil;
    [_colorLayer removeFromSuperlayer];
    _colorLayer = nil;
    _keyFrames = nil;
    _frameDict = nil;
    _imageName = nil;
    _index = 0;
}

-(NSMutableDictionary<NSNumber *,FlashViewFrameNode *> *)frameDict{
    if (!_frameDict) {
        _frameDict = [[NSMutableDictionary alloc] init];
    }
    return _frameDict;
}

-(CALayer *)layer{
    if (!_layer) {
        _layer = [[CALayer alloc] init];
    }
    return _layer;
}

//颜色叠加层
-(CALayer *)colorLayer{
    if (!_colorLayer) {
        _colorLayer = [[CALayer alloc] init];
    }
    return _colorLayer;
}

//模板层
-(CALayer *)maskLayer{
    if (!_maskLayer) {
        _maskLayer = [[CALayer alloc] init];
    }
    return _maskLayer;
}

/**
 * 获取线性插值
 * 其中旋转（skewX，skewY）同其他值有所不通。
 * flash中的逻辑是，这两个值一定在[-180, 180]之间，前后两个值相减的绝对值不能超过180才可以使用正常的线性插值，超过180的则需要将线性插值分为2部分：
 *   一是，先让oldValue同-180（或180，根据不通情况选择，见代码）进行插值
 *   二是，让-180（或180，根据不通情况选择，见代码）同newValue进行插值
 **/
-(NSNumber *)getPerValue: (FlashViewFrameNode *)new old:(FlashViewFrameNode*)old key:(NSString *)key per:(float) per{
    float oldValue = [[old valueForKey:key] floatValue];
    float newValue = [[new valueForKey:key] floatValue];
    float ret = -1;
    //计算跨度
    float span = fabsf(newValue - oldValue);
    if (span > 180 && ([key isEqualToString:@"skewX"] || [key isEqualToString:@"skewY"])) {//说明2个值不能直接变化需要跳板
        float realSpan = 360 - span;
        float mark = (oldValue < 0) ? -1 : 1;
        float mid = 180 * mark;
        float newStart = -mid;
        float midPer = (mid - oldValue) / realSpan;
        if (per < midPer) {
            ret = oldValue + per * realSpan * mark;
        }else{
            ret = newStart + (per - midPer) * realSpan * mark;
        }
    }else{
        ret = oldValue + per * (newValue - oldValue);
    }
    
    return @(ret);
}

//为每一帧计算数据
-(void) createFrameDict{
    if (self.frameDict.count > 0) {
        return;
    }
    for (int i = 0; i < self.keyFrames.count; i++) {
        FlashViewFrameNode *currFrameNode = self.keyFrames[i];
        FlashViewFrameNode *nextFrameNode = nil;
        if (currFrameNode.isTween && i < self.keyFrames.count - 1) {
            nextFrameNode = self.keyFrames[i + 1];
        }
        for (int j = currFrameNode.frameIndex; j < currFrameNode.frameIndex + currFrameNode.duration; j++) {
            FlashViewFrameNode *targetFrameNode = nil;
            if (!nextFrameNode) {
                targetFrameNode = currFrameNode;
            }else{
                CGFloat per = (j - currFrameNode.frameIndex) * 1.0 / (nextFrameNode.frameIndex - currFrameNode.frameIndex);
                targetFrameNode = [[FlashViewFrameNode alloc] init];
                targetFrameNode.x = [[self getPerValue:nextFrameNode old:currFrameNode key:@"x" per:per] floatValue];
                targetFrameNode.y = [[self getPerValue:nextFrameNode old:currFrameNode key:@"y" per:per] floatValue];
                targetFrameNode.scaleX = [[self getPerValue:nextFrameNode old:currFrameNode key:@"scaleX" per:per] floatValue];
                targetFrameNode.scaleY = [[self getPerValue:nextFrameNode old:currFrameNode key:@"scaleY" per:per] floatValue];
                
                targetFrameNode.skewX = [[self getPerValue:nextFrameNode old:currFrameNode key:@"skewX" per:per] floatValue];
                targetFrameNode.skewY = [[self getPerValue:nextFrameNode old:currFrameNode key:@"skewY" per:per] floatValue];
                
                targetFrameNode.alpha = [[self getPerValue:nextFrameNode old:currFrameNode key:@"alpha" per:per] floatValue];
                targetFrameNode.r = [[self getPerValue:nextFrameNode old:currFrameNode key:@"r" per:per] charValue];
                targetFrameNode.g = [[self getPerValue:nextFrameNode old:currFrameNode key:@"g" per:per] charValue];
                targetFrameNode.b = [[self getPerValue:nextFrameNode old:currFrameNode key:@"b" per:per] charValue];
                targetFrameNode.a = [[self getPerValue:nextFrameNode old:currFrameNode key:@"a" per:per] charValue];
                
                targetFrameNode.imageName = currFrameNode.imageName;
            }
            self.frameDict[@(j)] = targetFrameNode;
        }
    }
}

//角度转弧度
#define ANGLE_TO_RADIUS(angle) (0.01745329252f * (angle))

//根据数据更新图片的各种信息
-(void) updateLayerViewWithFrameNode:(FlashViewFrameNode *)frameNode{
    if (!frameNode || frameNode.isEmpty) {
        [_layer removeFromSuperlayer];
        [_colorLayer removeFromSuperlayer];
        return;
    }
    
    CALayer *layer = self.layer;
    if (!layer.superlayer) {
        [self.tool.baseView.layer addSublayer:layer];
    }
    
    if (!self.tool.isUseImplicitAnim) {
        //关闭隐式动画
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
    }
    
    //设置图片
    if (!self.imageName || ![frameNode.imageName isEqualToString:self.imageName]) {
        UIImage *image = [self.tool imageWithName:frameNode.imageName];
        layer.contents = (__bridge id _Nullable)(image.CGImage);
        layer.bounds = CGRectMake(0, 0, image.size.width * self.tool.scale.x, image.size.height * self.tool.scale.y);
        layer.position = CGPointMake(self.tool.baseView.layer.bounds.size.width / 2, self.tool.baseView.layer.bounds.size.height / 2);
        self.imageName = frameNode.imageName;
    }
    
    CGAffineTransform transform = CGAffineTransformIdentity;
    //旋转
    if(frameNode.skewX == frameNode.skewY){
        float radius = ANGLE_TO_RADIUS(frameNode.skewX);
        transform = CGAffineTransformMake(cosf(radius), sinf(radius), -sinf(radius), cosf(radius), 0, 0);
    } else {
        float radiusX = ANGLE_TO_RADIUS(frameNode.skewX);
        float radiusY = ANGLE_TO_RADIUS(frameNode.skewY);
        float cx = cosf(radiusX);
        float sx = sinf(radiusX);
        float cy = cosf(radiusY);
        float sy = sinf(radiusY);
        
        float a = cy * transform.a - sx * transform.b;
        float b = sy * transform.a + cx * transform.b;
        float c = cy * transform.c - sx * transform.d;
        float d = sy * transform.c + cx * transform.d;
        float tx = cy * transform.tx - sx * transform.ty;
        float ty = sy * transform.tx + cx * transform.ty;
        
        transform = CGAffineTransformMake(a, b, c, d, tx, ty);
    }
    
    //缩放
    transform = CGAffineTransformScale(transform, frameNode.scaleX, frameNode.scaleY);
    
    //平移
    transform.tx = frameNode.x * self.tool.scale.x;
    transform.ty = -frameNode.y * self.tool.scale.y;
    
    CATransform3D t3d = CATransform3DMakeAffineTransform(transform);
    t3d.m43 = self.index;
    layer.transform = t3d;
    
    //透明度
    layer.opacity = frameNode.alpha / 255;
    
    //颜色叠加
    if (frameNode.a != 0 && layer.opacity) {
        if (!self.colorLayer.superlayer) {
            [self.tool.baseView.layer addSublayer:self.colorLayer];
        }
        if (!self.colorLayer.mask) {
            self.colorLayer.mask = self.maskLayer;
        }
        
        self.maskLayer.contents = layer.contents;
        self.maskLayer.frame = self.colorLayer.bounds;
        
        self.colorLayer.backgroundColor = [UIColor colorWithRed:frameNode.r / 255.0 green:frameNode.g / 255.0 blue:frameNode.b / 255.0 alpha:frameNode.a / 255.0].CGColor;
        self.colorLayer.bounds = layer.bounds;
        self.colorLayer.position = layer.position;
        self.colorLayer.transform = layer.transform;
    }else{
        [self.colorLayer removeFromSuperlayer];
    }
    
    if (!self.tool.isUseImplicitAnim) {
        //关闭隐式动画
        [CATransaction commit];
    }
}

-(void)updateToIndex:(NSInteger)index{
    [self updateLayerViewWithFrameNode:self.frameDict[@(index)]];
}

-(void)trigerEventWithIndex:(NSInteger)index delegate:(id<FlashViewDelegate>)delegate{
    FlashViewFrameNode *frameNode = self.frameDict[@(index)];
    if (frameNode.mark && frameNode.mark.length > 0) {
        [delegate onEvent:FlashViewEventMark
                     data:@{
                            @"mark":frameNode.mark,
                            @"index":@(frameNode.frameIndex),
                            @"imageName": frameNode.imageName,
                            @"layerIndex": @(self.index)
                            }];
    }
}

//添加帧数据
-(void)addKeyFrame:(FlashViewFrameNode *)keyFrame{
    [(NSMutableArray *)self.keyFrames addObject:keyFrame];
}

-(NSMutableArray<FlashViewFrameNode *> *)keyFrames{
    if (!_keyFrames) {
        _keyFrames = [[NSMutableArray alloc] init];
    }
    return _keyFrames;
}
@end

//单个动画数据
@interface FlashViewAnimNode()
@property (nonatomic, strong) NSMutableArray<FlashViewLayerNode *> *layers;
@end

@implementation FlashViewAnimNode

-(void)onReady{
    for (FlashViewLayerNode *layerNode in self.layers) {
        [layerNode onReady];
    }
}

-(void)onClean{
    for (FlashViewLayerNode *layerNode in self.layers) {
        [layerNode onClean];
    }
    _layers = nil;
}

-(void) addLayer:(FlashViewLayerNode *) layer{
    [(NSMutableArray *)self.layers addObject:layer];
}

-(NSMutableArray<FlashViewLayerNode *> *)layers{
    if (!_layers) {
        _layers = [[NSMutableArray alloc] init];
    }
    return _layers;
}

-(void)updateToIndex:(NSInteger)index{
    for (FlashViewLayerNode *layerNode in self.layers) {
        [layerNode updateToIndex:index];
    }
}

-(void)trigerEventWithIndex:(NSInteger)index delegate:(id<FlashViewDelegate>)delegate{
    for (FlashViewLayerNode *layerNode in self.layers) {
        [layerNode trigerEventWithIndex:index delegate:delegate];
    }
}

@end

//所有动画
@interface FlashViewNode()
@property (nonatomic, strong) NSMutableDictionary<NSString *, FlashViewAnimNode*> *anims;
@end

@implementation FlashViewNode

-(void)onReady{
    for (NSString *key in self.anims) {
        FlashViewAnimNode *animNode = self.anims[key];
        [animNode onReady];
    }
}

-(void)onClean{
    for (NSString *key in self.anims) {
        FlashViewAnimNode *animNode = self.anims[key];
        [animNode onClean];
    }
    _anims = nil;
}

-(void) addAnim:(FlashViewAnimNode *)anim{
    [(NSMutableDictionary *)self.anims setObject:anim forKey:anim.animName];
}

-(NSMutableDictionary<NSString *,FlashViewAnimNode *> *)anims{
    if (!_anims) {
        _anims = [[NSMutableDictionary alloc] init];
    }
    return _anims;
}

@end


