module Main exposing (main)

import AnimationFrame
import Html exposing (Html)
import Html.Attributes exposing (height, style, width)
import List.Extra as List
import Math.Matrix4 as Mat4 exposing (Mat4)
import Math.Vector3 as Vec3 exposing (Vec3, vec3)
import Time exposing (Time)
import WebGL exposing (Mesh, Shader)
import WebGL.Settings.Blend as Blend
import WebGL.Settings.DepthTest as Depth
import WebGL.Settings.StencilTest as Stencil exposing (keep)


main : Program Never Time Time
main =
    Html.program
        { init = ( 0, Cmd.none )
        , view = view
        , subscriptions = \model -> AnimationFrame.diffs Basics.identity
        , update = \elapsed currentTime -> ( elapsed + currentTime, Cmd.none )
        }


view : Float -> Html msg
view t =
    WebGL.toHtmlWith
        [ WebGL.stencil 0
        , WebGL.depth 1
        ]
        [ width 400
        , height 400
        , style [ ( "display", "block" ) ]
        ]
        (let
            models =
                [ Mat4.makeRotate (t / 1000) (vec3 0 1 0)
                    |> Mat4.rotate 0.4 (vec3 1 0 0)
                , Mat4.makeTranslate <| vec3 0.8 0 3
                ]
         in
         [ List.map ambient models
         , List.map shadow models
         , List.map light models
         ]
            |> List.concat
        )


lightdir =
    vec3 0 -0.2 1
        |> Vec3.normalize


ambient model =
    WebGL.entity
        vert
        ambientFrag
        mesh
        { model = model, perspective = perspective }


shadow model =
    WebGL.entityWith
        [ Stencil.testSeparate { ref = 0, mask = 0xFF, writeMask = 0xFF }
            { test = Stencil.always, fail = Stencil.keep, zfail = Stencil.incrementWrap, zpass = Stencil.keep }
            { test = Stencil.always, fail = Stencil.keep, zfail = Stencil.decrementWrap, zpass = Stencil.keep }
        , Depth.less { write = False, near = 0, far = 1 }
        ]
        shadowVert
        shadowFrag
        shadowMesh
        { model = model, perspective = perspective, lightDirection = lightdir }


light model =
    WebGL.entityWith
        [ Stencil.test { ref = 0, test = Stencil.equal, mask = 0xFF, writeMask = 0, fail = keep, zfail = keep, zpass = keep }
        , Depth.lessOrEqual { write = False, near = 0, far = 1 }

        -- blending requires a gamma correction stage. Blend.add Blend.one Blend.one
        ]
        vert
        lightFrag
        mesh
        { model = model, perspective = perspective, lightDirection = lightdir, lightColor = vec3 0.8 0.2 0.2 }


perspective : Mat4
perspective =
    Mat4.mul
        (Mat4.makePerspective 45 1 0.01 100)
        (Mat4.makeLookAt (vec3 0.8 0.3 -0.6 |> Vec3.scale 8) (vec3 1.2 0 0) (vec3 0 1 0))


type alias Vertex =
    { position : Vec3
    , normal : Vec3
    }


mesh =
    WebGL.triangles cube


shadowMesh : Mesh Vertex
shadowMesh =
    WebGL.triangles (glueEdges cube)


cube =
    let
        rft =
            vec3 1 1 1

        lft =
            vec3 -1 1 1

        lbt =
            vec3 -1 -1 1

        rbt =
            vec3 1 -1 1

        rbb =
            vec3 1 -1 -1

        rfb =
            vec3 1 1 -1

        lfb =
            vec3 -1 1 -1

        lbb =
            vec3 -1 -1 -1
    in
    [ quad rft rfb rbb rbt
    , quad lft lfb rfb rft
    , quad rbt lbt lft rft
    , quad rfb lfb lbb rbb
    , quad lbt lbb lfb lft
    , quad rbt rbb lbb lbt
    ]
        |> List.concat
        |> List.map
            (\(( a, b, c ) as x) ->
                let
                    n =
                        normal x
                in
                ( Vertex a n, Vertex b n, Vertex c n )
            )


glueEdges tris =
    let
        edges =
            List.map (\( a, b, c ) -> [ ( a, b ), ( b, c ), ( c, a ) ]) tris
                |> List.concat
                |> List.map (\( v1, v2 ) -> ( ( v1.position, v2.position ), v1.normal ))

        glue =
            List.filter (\( ( a, b ), _ ) -> Vec3.toTuple a < Vec3.toTuple b) edges
                |> List.map
                    (\( ( a, b ), n1 ) ->
                        let
                            n2 =
                                List.find (Tuple.first >> (==) ( b, a )) edges
                                    |> Maybe.map Tuple.second
                                    |> Maybe.withDefault (vec3 0 0 0)

                            -- (Debug.crash "fucked up winding")
                        in
                        quad (Vertex b n1) (Vertex a n1) (Vertex a n2) (Vertex b n2)
                    )
                |> List.concat
    in
    tris ++ glue


normal ( a, b, c ) =
    Vec3.cross (Vec3.sub b a) (Vec3.sub a c)
        |> Vec3.normalize


quad a b c d =
    [ ( a, b, c ), ( c, d, a ) ]



-- Shaders


type alias Uniforms a =
    { a | model : Mat4, perspective : Mat4 }


vert : Shader Vertex { a | model : Mat4, perspective : Mat4 } { normal_v : Vec3 }
vert =
    [glsl|
        attribute vec3 position;
        attribute vec3 normal;
        varying vec3 normal_v;

        uniform mat4 model;
        uniform mat4 perspective;

        void main () {
            normal_v = (model * vec4(normal, 0.0)).xyz;
            gl_Position = perspective * model * vec4(position, 1.0);
        }
    |]


ambientFrag : Shader {} (Uniforms a) { normal_v : Vec3 }
ambientFrag =
    [glsl|
        precision mediump float;
        varying vec3 normal_v;

        void main () {
            vec3 linear = vec3(0.1);
            gl_FragColor = vec4(pow(linear, vec3(1.0/2.2)), 1.0);
        }
    |]


lightFrag : Shader {} { a | lightColor : Vec3, lightDirection : Vec3 } { normal_v : Vec3 }
lightFrag =
    [glsl|
        precision mediump float;

        varying vec3 normal_v;

        uniform vec3 lightColor;
        uniform vec3 lightDirection;

        void main () {
            vec3 linear = vec3(0.1) + lightColor * -dot(lightDirection, normal_v);
            gl_FragColor = vec4(pow(linear, vec3(1.0/2.2)), 1.0);
        }
    |]


shadowVert : Shader Vertex (Uniforms { a | lightDirection : Vec3 }) {}
shadowVert =
    [glsl|
        attribute vec3 position;
        attribute vec3 normal;

        uniform mat4 model;
        uniform mat4 perspective;
        uniform vec3 lightDirection;


        void main () {
            vec3 rotatedNormal = (model * vec4(normal, 0.0)).xyz;

            gl_Position = perspective
                * (dot(rotatedNormal, lightDirection) > 0.0
                    ? vec4(lightDirection, 0.0)
                    : model * vec4(position, 1.0));
        }
    |]


shadowFrag : Shader {} a {}
shadowFrag =
    [glsl|
        precision mediump float;
        void main () {
            //gl_FragColor = vec4(1.0);
        }
    |]
