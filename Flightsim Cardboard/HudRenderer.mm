//
//  HudRenderer.m
//  Flightsim Cardboard
//
//  Created by Sean Purcell on 2016-02-07.
//  Copyright © 2016 Sean Purcell. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <OpenGLES/ES2/glext.h>

#import "CardboardSDK.h"

#import "glmheaders.hpp"
#import "rotation.hpp"
#import "lodepng.h"

#import <vector>

static size_t updateHudVertices(vec3 pos, quat facing, vec3 vel);

#pragma mark - Objective-C interface

@interface HudRenderer : NSObject {
	GLuint _program;
	
	GLuint _vertexArray;
	
	GLint _positionLoc;
	GLint _texcoordLoc;
	
	GLint _hudColorLoc;
	GLint _projViewLoc;
	
	GLuint _tex;
	
	GLuint _vbo, _ebo;
	
	GLKMatrix4 _headViewInv;
	quat _facing;
	vec3 _pos, _vel;
	
	size_t _indNum;
}

@end

@implementation HudRenderer

- (instancetype)init
{
	self = [super init];
	if(!self) { return nil; }
	
	return self;
}

- (void)setupRendererWithView:(GLKView *)glView
{
	[EAGLContext setCurrentContext: glView.context];
	
	[self setupProgram];
	[self setupVAOS];
	
	glEnable(GL_DEPTH_TEST);
	
	GLCheckForError();
}

- (BOOL)setupProgram
{
	NSString *path = nil;
	
	GLuint vertexShader = 0;
	path = [[NSBundle mainBundle] pathForResource:@"HudShader" ofType:@"vsh"];
	if(!GLCompileShaderFromFile(&vertexShader, GL_VERTEX_SHADER, path)) {
		NSLog(@"Failed to compile shader at %@", path);
		return NO;
	}
	
	GLuint fragmentShader = 0;
	path = [[NSBundle mainBundle] pathForResource:@"HudShader" ofType:@"fsh"];
	if(!GLCompileShaderFromFile(&fragmentShader, GL_FRAGMENT_SHADER, path)) {
		NSLog(@"Failed to compile shader at %@", path);
		return NO;
	}
	
	_program = glCreateProgram();
	glAttachShader(_program, vertexShader);
	glAttachShader(_program, fragmentShader);
	GLLinkProgram(_program);
	
	glUseProgram(_program);
	
	GLCheckForError();
	
	return YES;
}

- (void)setupVAOS
{
	_positionLoc = glGetAttribLocation(_program, "position");
	_texcoordLoc = glGetAttribLocation(_program, "texcoord");
	
	_hudColorLoc = glGetUniformLocation(_program, "hudColor");
	_projViewLoc = glGetUniformLocation(_program, "projView");
	
	glGenVertexArraysOES(1, &_vertexArray);
	glBindVertexArrayOES(_vertexArray);
	
	glGenBuffers(1, &_vbo);
	glGenBuffers(1, &_ebo);
	
	glEnableVertexAttribArray(_positionLoc);
	glEnableVertexAttribArray(_texcoordLoc);
	
	[self setupTex];

	GLCheckForError();
}

- (void)setupTex
{
	/* load and buffer the texture */
	glGenTextures(1, &_tex);
	glActiveTexture(GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D, _tex);
	
	NSString *path = [[NSBundle mainBundle] pathForResource:@"text" ofType:@"png"];
	std::vector<unsigned char> image;
	unsigned width, height;
	unsigned error = lodepng::decode(image, width, height, [path UTF8String]);
	if(error) NSLog(@"decoder error %d: %s", error, lodepng_error_text(error));
	
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, &image[0]);
	//glGenerateMipmap(GL_TEXTURE_2D);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	
	GLCheckForError();
}

- (void)setHudColor:(vec4) hudColor
{
	glUseProgram(_program);
	glUniform4fv(_hudColorLoc, 1, value_ptr(hudColor));
}

- (void)shutdownRendererWithView:(GLKView *)glView
{
}

- (void)renderViewDidChangeSize:(CGSize)size
{
}

- (void)updateWithPos:(vec3) pos andFacing:(quat)facing andVel:(vec3) vel andHeadView:(GLKMatrix4)headView
{
	_headViewInv = GLKMatrix4Invert(headView, NULL);
	_facing = facing;
	_pos = pos;
	_vel = vel;
	
	_indNum = [self updateHudVertices];
}

- (void)drawEyeWithEye:(CBDEye *)eye
{
	glDisable(GL_DEPTH_TEST);
	glEnable(GL_BLEND);
	
	//DLog(@"%ld %@", eye.type, NSStringFromGLKMatrix4([eye eyeViewMatrix]));
	
	GLCheckForError();
	
	GLKMatrix4 perspective = [eye perspectiveMatrixWithZNear:0.1f zFar: 10.f];
	
	GLKMatrix4 view = GLKMatrix4Multiply(_headViewInv, [eye eyeViewMatrix]);
	
	GLKMatrix4 projView = GLKMatrix4Multiply(perspective, view);
	
	glUseProgram(_program);
	glBindVertexArrayOES(_vertexArray);
	
	glUniformMatrix4fv(_projViewLoc, 1, 0, projView.m);
	
	[self drawHud];
	
	glBindVertexArrayOES(0);
	glUseProgram(0);
}

- (void)drawHud
{
	glBindBuffer(GL_ARRAY_BUFFER, _vbo);
	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _ebo);
	
	glVertexAttribPointer(_positionLoc, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(GLfloat),
						  (void*)0);
	glVertexAttribPointer(_texcoordLoc, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(GLfloat),
						  (void*)(3 * sizeof(GLfloat)));
	
	glDrawElements(GL_TRIANGLES, (int) _indNum, GL_UNSIGNED_SHORT, 0);
}

- (void)finishFrameWithViewportRect:(CGRect)viewPort
{
}

#pragma mark - Original HUD C++ functions
static void setColors(std::vector<GLfloat> &vertices, char c) {
	const char C[] = { '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
		'N', 'E', 'S', 'W', 'D', 'C', 'F' };
	int num = sizeof(C)/sizeof(C[0]);
	float topleft = 0.0f;
	float width = 1.f / num;
	int i;
	for(i = 0; i < num; i++) {
		if(C[i] == c) {
			break;
		}
	}
	topleft = (float)min(i, num - 1) * width;
	
	size_t ind = vertices.size() - 20;
	vertices[ind + 3] = topleft;
	vertices[ind + 4] = 0.0f;
	ind += 5;
	vertices[ind + 3] = topleft + width;
	vertices[ind + 4] = 0.0f;
	ind += 5;
	vertices[ind + 3] = topleft + width;
	vertices[ind + 4] = 1.0f;
	ind += 5;
	vertices[ind + 3] = topleft;
	vertices[ind + 4] = 1.0f;
}

- (size_t) updateHudVertices
{
#define quad() do {\
size_t start = vertices.size() / 5 - 4;\
indices.push_back(start + 0);\
indices.push_back(start + 1);\
indices.push_back(start + 3);\
indices.push_back(start + 2);\
indices.push_back(start + 1);\
indices.push_back(start + 3);\
} while(0)
	
#define vertex(v) do {\
vertices.push_back((v).x);\
vertices.push_back((v).y);\
vertices.push_back((v).z);\
vertices.push_back(0.f);\
vertices.push_back(0.f);\
} while(0)
	
#define colors(c) do {\
setColors(vertices, c);\
} while(0)
	
#define digit(tl, r, d, c) do {\
vertex(tl); \
vertex(tl + r); \
vertex(tl + r + d); \
vertex(tl + d); \
colors(c); \
quad(); \
} while(0)
	
#define rect(tl, r, d, c) do {\
digit(tl, r, d, c);\
} while(0)
	
	vec3 pos = _pos;
	quat facing = _facing;
	vec3 vel = _vel;
	
	std::vector<GLfloat> vertices;
	std::vector<GLushort> indices;
	
	Euler angles = Euler::fromRotation(facing); // This method automatically converts the coordinates. See rotation.cpp.
	
	quat roll = angleAxis(angles.roll, vec3(0, 0, 1));
	vec3 right = roll * vec3(1, 0, 0);
	vec3 rperp = roll * vec3(0, 1, 0);
	
	quat pitch = angleAxis(angles.pitch, right);
	vec3 forw = pitch * vec3(0, 0, 1);
	
	/* draw a cross hair representing velocity direction */
	{
		vec3 cright = right;
		vec3 cup = rperp;
		quat velfix = angleAxis(-angles.yaw, vec3(0, 1, 0)) *
		angleAxis(-angles.pitch, vec3(1, 0, 0)) *
		angleAxis(-angles.roll, vec3(0, 0, 1));
		vec3 vels = normalize(vel) * velfix;
		vels = vels - 2 * dot(vels, right) * right;
		//vels = angleAxis(-angles.yaw, vec3(0, 1, 0)) * vels;
		rect(-0.1f * cright + 0.01f * cup + vels * 5.f, 0.2f * cright,
			 -0.02f * cup, 'F');
		rect(-0.01f * cright + vels * 5.f, 0.02f * cright,
			 0.1f * cup, 'F');
	}
	
	/* draw an arrow in the middle */
	{
		vec3 start(0, 0, 5.f);
		vec3 dr = vec3(0.15f, -0.06f, 0); vec3 drp(-dr.y, dr.x, 0);
		vec3 dl = dr; dl.x = -dl.x;       vec3 dlp(-dl.y, dl.x, 0);
		vec3 ur = vec3(dl.x + 0.01f, 0.12f, 0);   vec3 urp(-ur.y, ur.x, 0);
		vec3 ul = vec3(dr.x + 0.01f, ur.y, 0);    vec3 ulp(-ul.y, ul.x, 0);
		
		drp = normalize(drp);
		dlp = normalize(dlp);
		urp = normalize(urp);
		ulp = normalize(ulp);
		
		rect(start - 0.01f * drp, dr, drp * 0.02f, 'F');
		rect(start - 0.01f * dlp, dl, dlp * 0.02f, 'F');
		rect(start + dr - 0.01f * urp, ur, urp * 0.02f, 'F');
		rect(start + dl - 0.01f * ulp, ul, ulp * 0.02f, 'F');
	}
	
	vec3 vec = forw * 1.f;
	float linewidth = 0.75f;
	quat rot = angleAxis(-(float)M_PI/36, right);
	for(int a = 0; a < 360; a += 5, vec = rot * vec) {
		if(acos(dot(vec, vec3(0, 0, 1))) > 15 * M_PI / 180.f) {
			continue;
		}
		
		float width;
		if(a % 10 == 5) {
			width = linewidth / 2;
		} else {
			width = linewidth;
		}
		vec3 v1 = vec * 5.f + rperp * -0.01f - right / 2.f * width;
		vec3 v4 = vec * 5.f + rperp * 0.01f  - right / 2.f * width;
		vec3 v2 = v1 + right * width;
		vec3 v3 = v4 + right * width;
		
		vertex(v1);
		vertex(v2);
		vertex(v3);
		vertex(v4);
		colors('F');
		quad();
		
		int ang;
		if(a <= 90) {
			ang = a;
		} else if(a <= 270) {
			ang = 180 - a;
		} else {
			ang = a - 360;
		}
		vec3 dr = 0.075f * right;
		vec3 dd = -0.1f * rperp;
		vec3 L = (v1 + v4) / 2.f;
		vec3 R = (v3 + v2) / 2.f;
		if(ang < 0) {
			digit(L - dr * 3.f - dd * 0.5f, dr, dd, '-');
			digit(R - dd * 0.5f, dr, dd, '-');
			R += dr;
			ang = -ang;
		}
		digit(L - dr * 2.f - dd * 0.5f, dr, dd, (ang % 100) / 10 + '0');
		digit(L - dr * 1.f - dd * 0.5f, dr, dd, (ang % 10) + '0');
		digit(R + dr * 0.f - dd * 0.5f, dr, dd, (ang % 100) / 10 + '0');
		digit(R + dr * 1.f - dd * 0.5f, dr, dd, (ang % 10) + '0');
	}
	
	/* draw the heading */
	float tickwidth = 10.f / 360.f;
	float tickheight = 0.1f;
	float headwidth = tickwidth * 90.f;
	vec3 basis((360 -angles.yawd()) * tickwidth, 2.f, 5.f);
	vec3 mov(tickwidth, 0, 0);
	vec = basis;
	
	for(int a = 0; a < 360; a+=5, vec += 5.f*mov) {
		if(vec.x > headwidth / 2.f) {
			vec.x -= 360 * tickwidth;
		}
		if(vec.x < -headwidth / 2.f) continue;
		
		if(a % 90 == 0) {
			vec3 right(tickheight, 0, 0);
			vec3 down(0, -tickheight / 0.75f, 0);
			char c = a == 0 ? 'N' : (a == 90 ? 'E' : (a == 180 ? 'S' : 'W'));
			digit(vec - 0.5f * right - tickheight / 2.f - down.y / 2.f, right, down, c);
			continue;
		}
		vec3 right(0.02f, 0, 0);
		vec3 down(0, -tickheight, 0);
		if(a % 10 == 0) {
			rect(vec - 0.5f*right, right, down, 'F');
		} else {
			rect(vec - 0.5f*right+0.25f*down, right, 0.5f*down, 'F');
		}
	}
	
	/* draw airspeed indicator */
	float airspeed = length(vel);
	float asheight = 2.f;
	
	vec3 asbasis(-2.f, 0.f, 5.f);
	vec3 astickh(0.f, asheight/50.f, 0.f);
	vec3 astickw(-0.3f, 0, 0);
	rect(asbasis - vec3(0, asheight / 2.f, 0), vec3(0.02f, 0, 0), vec3(0, asheight, 0),
		 'F');
	//rect(asbasis, vec3(0.1f, 0.1f, 0.f), normalize(vec3(1, -1, 0)) * 0.02f, 'F');
	//rect(asbasis, vec3(0.1f, -0.1f, 0.f), normalize(vec3(1, 1, 0)) * 0.02f, 'F');
	rect(asbasis-vec3(0,0.01f,0), vec3(0.1f, 0, 0), vec3(0, 0.02f, 0), 'F');
	
	int asiv = (int) (airspeed - 50); asiv = asiv - asiv % 10;
	asiv = max(0, asiv);
	for(int v = asiv; v - airspeed <= 50; v += 5) {
		vec3 yvec = astickh * (v - airspeed);
		if(yvec.y > asheight / 2. || yvec.y < -asheight / 2.) continue;
		
		if(v % 10 == 0) {
			rect(asbasis + yvec - vec3(0, 0.01f, 0), astickw, vec3(0, 0.02f, 0), 'F');
			vec3 L = asbasis + yvec + astickw;
			int d = v;
			vec3 dr = 0.075f * vec3(1, 0, 0);
			vec3 dd = 0.1f * vec3(0, -1, 0);
			while(d) {
				rect(L - dr - 0.5f*dd, dr, dd, '0' + d % 10);
				d = d / 10;
				L -= dr;
			}
		} else {
			rect(asbasis + yvec - vec3(0, 0.01f, 0), astickw / 1.5f, vec3(0, 0.02f, 0), 'F');
		}
	}
	
	float alheight = asheight;
	vec3 albasis(2.f, 0.f, 5.f);
	vec3 altickh(0.f, alheight/500.f, 0.f);
	vec3 altickw(0.3f, 0, 0);
	rect(albasis - vec3(0, alheight / 2.f, 0), vec3(0.02f, 0, 0), vec3(0, asheight, 0),
		 'F');
	rect(albasis-vec3(0,0.01f,0), vec3(-0.1f, 0, 0), vec3(0, 0.02f, 0), 'F');
	int aliv = (int) (pos.y - 250); aliv = aliv - aliv % 50;
	for(int v = aliv; v - pos.y <= 250; v += 50) {
		vec3 yvec = altickh * (v - pos.y);
		if(yvec.y > alheight / 2. || yvec.y < -alheight / 2.) continue;
		
		if(v % 100 == 0) {
			rect(albasis + yvec - vec3(0, 0.01f, 0), altickw, vec3(0, 0.02f, 0), 'F');
			vec3 R = albasis + yvec + altickw;
			int d = v;
			vec3 dr = 0.075f * vec3(1, 0, 0);
			vec3 dd = 0.1f * vec3(0, -1, 0);
			if(d == 0) {
				rect(R - 0.5f * dd, dr, dd, '0');
			}
			if(d < 0) {
				d = -d;
				rect(R - 0.5f * dd, dr, dd, '-');
				R += dr;
			}
			int i = 1;
			while(d >= i) i *= 10;
			i/=10;
			while(i) {
				rect(R - 0.5f*dd, dr, dd, '0' + (d / i));
				d = d % i;
				i /= 10;
				R += dr;
			}
		} else {
			rect(albasis + yvec - vec3(0, 0.01f, 0), altickw / 1.5f, vec3(0, 0.02f, 0), 'F');
		}
	}
	
#undef quad
#undef vertex
#undef colors
	
	glUseProgram(_program);
	glBindVertexArrayOES(_vertexArray);
	
	glBindBuffer(GL_ARRAY_BUFFER, _vbo);
	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _ebo);
	
	glBufferData(GL_ARRAY_BUFFER, vertices.size() * sizeof(GLfloat),
				 &vertices[0], GL_DYNAMIC_DRAW);
	glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.size() * sizeof(GLushort),
				 &indices[0], GL_DYNAMIC_DRAW);
	return indices.size();
}

@end
